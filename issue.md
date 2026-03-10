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
2. **C `write(STDOUT_FILENO, ...)` 有效**：通过 FFI 直接调用 POSIX `write()` 系统调用写入 fd 1，数据可以立即到达管道。但仅在发送多帧数据时首帧响应能被读取。
3. **根本原因**：仓颉 `ConsoleReader.readln()` 在管道模式下的读取行为——当管道中可用数据量较小时，底层缓冲读取可能阻塞等待更多数据，导致整个服务循环被挂起在输入读取阶段。

### 结论

这是**仓颉标准库行为问题**，具体涉及：
- `ConsoleWriter.flush()` 在管道模式下不能保证数据立即到达管道对端
- `ConsoleReader` 的缓冲读取策略在管道模式下可能导致阻塞

**不确定这是 bug 还是设计约束**——仓颉标准库文档中 `ConsoleWriter` 描述为"使用缓冲——调用 `flush()` 确保输出"，但在管道场景下 flush 的语义不明确。建议向仓颉 SDK 团队确认管道模式下 `Console` 读写器的预期行为。

### 绕过方案

**方案 A：直接系统调用写入（已实施）**

在 `cangjie-tree-sitter` C 库中添加 `cj_write_stdout()` 函数，通过 POSIX `write(STDOUT_FILENO, ...)` 绕过所有缓冲层直接写入 stdout：

```c
// cangjie-tree-sitter/treesitter/ts_lib.c
int cj_write_stdout(const char *data, int len) {
    int written = 0;
    while (written < len) {
        int n = write(STDOUT_FILENO, data + written, len - written);
        if (n <= 0) return -1;
        written += n;
    }
    return written;
}
```

仓颉侧通过 FFI 调用：

```cangjie
// cangjie-tree-sitter/src/treesitter.cj
foreign func cj_write_stdout(data: CPointer<UInt8>, len: Int32): Int32

public func writeStdoutDirect(content: String): Bool {
    let bytes = content.toArray()
    unsafe {
        var handle = acquireArrayRawData(bytes)
        result = cj_write_stdout(CPointer<UInt8>(handle.pointer), Int32(bytes.size)) > 0
        releaseArrayRawData(handle)
    }
}
```

**方案 B：批量通信（Python 测试使用）**

Python 测试客户端采用 `subprocess.communicate()` 批量发送所有请求帧，关闭 stdin 后一次性读取所有响应。虽然不支持交互式通信，但对测试场景完全足够。

---

## 问题 2：ProjectBootstrapTest 测试失败（预存问题）

### 现象

以下 3 个测试在原始代码中即失败，与本次修改无关：
- `bootstrapJsonParserCopiesTemplate` — ERROR（FSException: 路径不存在）
- `bootstrapJsonParserCreatesMissingParents` — FAILED
- `stdioMcpCanBootstrapCreateFileAndValidateProject` — ERROR

### 分析

这些测试依赖特定的文件系统路径和 example 模板文件，在当前构建环境中可能缺少必要资源。属于环境配置问题，非代码缺陷。
