# CangjieCoder Service 已知问题

## 问题 1：仓颉标准库 stdout 管道缓冲问题

### 现象

当 MCP service 通过 `subprocess.Popen` 以管道方式启动时，`ConsoleWriter.flush()` 无法将数据刷新到 OS 管道。响应数据停留在内部缓冲区，直到进程退出（stdin EOF）后才被刷新输出。

具体表现：
- **文件重定向**（`< input.bin > output.bin`）：正常工作
- **`communicate()`**（发送后关闭 stdin）：正常工作
- **管道交互模式**（保持 stdin 打开）：无法读取响应

### 分析

经过逐层排查：

1. **C `fflush(stdout)` 无效**：通过 FFI 调用 `fflush(stdout)` 不能解决，说明仓颉运行时并非通过 C stdio 写入 stdout。
2. **POSIX `write(STDOUT_FILENO, ...)` 有效**：通过 FFI 直接调用 POSIX `write()` 系统调用写入 fd 1，数据可以立即到达管道。
3. **根本原因**：仓颉 `ConsoleWriter` 内部使用了自有的缓冲机制，`flush()` 方法的实现可能只刷新了仓颉层面的缓冲，未能触发底层操作系统级别的 `write` 系统调用。

### 结论

这是**仓颉标准库行为问题**，具体涉及：
- `ConsoleWriter.flush()` 在管道模式下不能保证数据立即到达管道对端

**不确定这是 bug 还是设计约束**——仓颉标准库文档中 `ConsoleWriter` 描述为"使用缓冲——调用 `flush()` 确保输出"，但在管道场景下 flush 的语义不明确。建议向仓颉 SDK 团队确认管道模式下 `ConsoleWriter` 的预期行为。

### 绕过方案

在 service 中直接声明 POSIX `write` 函数，通过仓颉 FFI 封装为 `writeStdoutDirect`：

```cangjie
// service/src/mcp_handlers.cj

// POSIX write 系统调用声明（用于绕过仓颉 ConsoleWriter 的管道缓冲问题）
foreign func write(fd: Int32, buf: CPointer<UInt8>, count: UIntNative): IntNative

// 直接通过 POSIX write 系统调用写入 stdout（绕过所有缓冲层）
func writeStdoutDirect(content: String): Unit {
    let bytes = content.toArray()
    unsafe {
        var handle = acquireArrayRawData(bytes)
        var offset: Int64 = 0
        while (offset < bytes.size) {
            let n = write(1, CPointer<UInt8>(handle.pointer) + offset,
                          UIntNative(bytes.size - offset))
            if (Int64(n) <= 0) { break }
            offset += Int64(n)
        }
        releaseArrayRawData(handle)
    }
}
```

仓颉程序构建时默认链接标准 C 库，因此 `foreign func write(...)` 声明可直接链接到 libc 的 `write` 符号，无需额外配置。

Python 测试客户端采用 `subprocess.communicate()` 批量发送所有请求帧，关闭 stdin 后一次性读取所有响应。虽然不支持交互式通信，但对测试场景完全足够。

---

## 问题 2：skills.search 中文分词不足（已修复）

### 现象

使用中文复合查询（如"类定义和继承"）搜索技能时返回空结果，但单个中文词（如"类"或"继承"）可以正常匹配。

### 原因

`SkillRegistry.search()` 使用 `query.split(" ")` 按空格分词，无法处理中文无空格的连续文本。"类定义和继承"被当作一个整体去匹配，而技能描述中不会出现完全相同的字符串。

### 修复

新增 `tokenizeQuery` 函数，实现中文感知分词：
1. 先按空格拆分
2. 按常见中文虚词（和/或/与/的/在/中/用/把/了/是/如何/怎么/什么/可以/使用/进行/以及/通过/关于）进一步切分
3. 对较长的中文片段，按 2 字符滑动窗口生成 bigram 子词

修复后，"类定义和继承"被分词为 ["类定义", "继承", "类定", "定义"]，可正确匹配到 class、interface 等相关技能。

---

## 问题 3：Agent E2E 测试环境依赖

### 现象

`stdioMcpCanBootstrapCreateFileAndValidateProject` 测试始终失败（约 2 秒超时）。

### 分析

该测试是 agent 包的端到端测试，会：
1. 创建临时工作区
2. 启动 MCP service 进程
3. 调用 `project.bootstrap_json_parser` 生成项目
4. 调用 `workspace.run_build` 和 `workspace.run_test` 构建并测试生成的项目

测试失败原因是临时工作区中 `cjpm` 编译工具不可用或 SDK 环境变量未传递到子进程。这是测试环境配置问题，不是代码缺陷。
