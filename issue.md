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

## 问题 3：备份/回滚状态的会话级生命周期

### 问题发现

在编写 `e2etest_taskmanager` 端到端测试时，发现以下场景失败：在一个 MCP 会话中
执行 `edit_ast_node`（触发自动备份），然后在另一个会话中调用 `workspace.rollback`，
回滚报告成功 (`ok=true`)，但文件内容并未恢复。

```python
# 会话 1: 编辑文件（自动触发 backup）
c1 = client()
c1.start()
c1.call_tool("cangjie.edit_ast_node", {...})   # 内部调用 globalBackupStore.backup()
c1.execute()   # 进程退出 → globalBackupStore 被销毁

# 会话 2: 尝试回滚
c2 = client()
c2.start()
c2.call_tool("workspace.rollback")            # 新进程，globalBackupStore 为空
resp = c2.execute()
# resp[0]["ok"] == True, 但实际什么都没恢复
```

### 当前机制

**备份存储** (`service/src/common/backup.cj`):
- `FileBackupStore` 使用纯内存 `HashMap<String, String>` 保存文件原始内容
- `globalBackupStore` 是包级全局变量，进程启动时创建，进程退出时销毁
- `backup(path)` 采用首次写入保护：同一文件多次修改只保存最初版本
- `rollbackAll()` 恢复所有备份文件后清空 HashMap

**触发备份的工具** (3 处):
| 工具 | 位置 | 触发条件 |
|------|------|----------|
| `workspace.create_file` | `workspace/files.cj:108` | `overwrite=true` 且文件已存在 |
| `workspace.replace_text` | `workspace/files.cj:136` | 找到唯一匹配后、替换前 |
| `cangjie.edit_ast_node` | `analysis/handlers.cj:73` | AST 节点替换前 |

**进程模型** (`tests/mcp_client.py`):
每次 `McpClient.execute()` 启动一个全新的 `cangjiecoder mcp-stdio` 子进程，
通过 `proc.communicate()` 一次性发送所有请求帧，读取响应后进程退出。
因此，`globalBackupStore` 的生命周期与单次 `execute()` 调用完全一致。

### 状态生命周期图

```
┌─ McpClient.execute() ──────────────────────────────────┐
│                                                         │
│  subprocess.Popen("cangjiecoder mcp-stdio ...")         │
│  ┌─ 服务进程 ───────────────────────────────────────┐   │
│  │                                                   │   │
│  │  globalBackupStore = FileBackupStore()  ← 空的    │   │
│  │                                                   │   │
│  │  while (stdin 有数据) {                           │   │
│  │     请求 → 处理 → 响应                             │   │
│  │                                                   │   │
│  │     create_file(overwrite) → backup() → 写入      │   │
│  │     replace_text           → backup() → 替换      │   │
│  │     edit_ast_node          → backup() → 替换      │   │
│  │     rollback               → rollbackAll() → 恢复 │   │
│  │  }                                                │   │
│  │                                                   │   │
│  │  // stdin EOF → 循环结束                           │   │
│  │  // 进程退出 → globalBackupStore 销毁              │   │
│  └───────────────────────────────────────────────────┘   │
│                                                         │
│  proc.communicate() → 收集响应 → 返回                   │
└─────────────────────────────────────────────────────────┘
```

### 合理性评估

**合理的部分:**
- **简单可靠**: 纯内存存储不需要文件锁、序列化、临时文件清理
- **无副作用**: 进程退出自动清理，不留下 `.bak` 文件
- **事务语义**: 同一会话中的操作构成一个"事务"，可整体回滚
- **安全隔离**: 不同会话（进程）之间不会互相干扰

**局限的部分:**
- **跨会话回滚不可能**: 如果客户端在编辑后断开连接，备份丢失，修改不可撤销
- **空回滚静默成功**: `rollback` 在无备份时返回 `ok=true`（`count=0`），
  调用者可能误以为回滚成功，实际上什么都没恢复
- **与持久连接 Agent 的差距**: 真实 AI Agent 通常在多轮对话中保持长连接，
  而 MCP stdio 模式每次请求都是独立进程

### 与真实 Agent 使用场景的对比

| 场景 | MCP stdio (当前) | 持久连接 Agent |
|------|------------------|----------------|
| 编辑 → 编译 → 回滚 (同一轮) | ✅ 可行 | ✅ 可行 |
| 编辑 → 断开 → 重连 → 回滚 | ❌ 备份已丢失 | 取决于持久化 |
| 多轮对话中的增量回滚 | ❌ 每轮是新进程 | ✅ 状态保持 |
| 并发 Agent 的备份隔离 | ✅ 天然进程隔离 | 需要额外机制 |

### 测试中的规避方式

编辑和回滚必须放在同一个 `execute()` 调用中:

```python
# ✅ 正确做法: 同一会话中完成编辑-验证-回滚-验证
c = client()
c.start()
c.call_tool("workspace.read_file", {"path": "src/task.cj"})     # 1 原始
c.call_tool("cangjie.edit_ast_node", {...})                       # 2 编辑
c.call_tool("workspace.read_file", {"path": "src/task.cj"})     # 3 验证编辑
c.call_tool("workspace.rollback")                                 # 4 回滚
c.call_tool("workspace.read_file", {"path": "src/task.cj"})     # 5 验证恢复
resp = c.execute()
assert resp[5]["data"]["content"] == resp[1]["data"]["content"]  # ✅ 一致
```

### 可能的改进方向

1. **持久化备份**: 将备份 HashMap 序列化到磁盘（如 `.cangjiecoder/backups.json`），
   进程重启后可恢复
2. **区分空回滚的响应**: 当无备份时返回不同的 summary（如 "No pending backups"）
   而非简单的 `ok=true`，帮助调用者准确判断
3. **持久连接模式**: 通过 HTTP/WebSocket 长连接替代 stdio 的短生命周期进程模型

---

## 问题 4：edit_ast_node 依赖外部 tree-sitter CLI（已修复）

### 现象

`cangjie.edit_ast_node` 工具在所有环境中均失败，返回错误:
```
tree-sitter unavailable for AST edit: ProcessException: Created process failed,
errMessage: "No such file or directory".
```

### 原因

`editAstNode()` 函数（`service/src/analysis/analyzer.cj`）通过 `getVariable("TREE_SITTER_CANGJIE")`
获取外部 `tree-sitter` CLI 路径，然后 `spawn` 子进程执行 `tree-sitter parse <file>` 来获取
AST 节点坐标。这与其他所有 AST 工具（`ast_parse`、`ast_query_nodes`、`ast_summary` 等）
使用内置 tree-sitter FFI 的方式不一致。

而内置 FFI 的 `queryNodes()` 已经通过 C API 直接返回 `NodeInfo.startByte` / `NodeInfo.endByte`
字节偏移量——恰好是编辑替换所需要的信息。

### 修复

将 `editAstNode()` 改为使用内置 `queryNodes()` FFI:
- 删除外部 `tree-sitter` CLI 调用
- 直接使用 `NodeInfo.startByte` / `NodeInfo.endByte` 定位替换范围
- 从 ~35 行实现缩减到 ~20 行
- 零外部依赖，与其他 AST 工具保持一致

旧的辅助函数（`AstNodeMatch`、`parseTreeSitterNodeMatches`、`parseNodeCoordinate`、
`offsetForPoint`）保留，因为仍被 `analyzeCangjieFile` 的 tree-sitter CLI 分析路径使用，
且有独立的单元测试覆盖。

---

## 问题 5：lsp_probe 冷启动模式下 LSP 服务器响应丢失（已修复）

### 现象

`cangjie.lsp_probe` 工具在有 LSPServer 二进制可用的环境中仍返回失败:
```json
{
  "ok": false,
  "summary": "LSP probe returned JSON-RPC responses, but initialize did not succeed cleanly.",
  "data": {
    "responsePreview": "{\"error\":{\"code\":-32002,\"message\":\"server not initialized\"},\"id\":2,\"jsonrpc\":\"2.0\"}"
  }
}
```

### 原因

`probeLspServer()` 使用 `runLspSession()` 冷启动方式：将全部消息（initialize → initialized →
shutdown → exit）一次性写入子进程 stdin，然后通过 `waitOutput()` 关闭 stdin 并读取所有 stdout。

问题在于 `waitOutput()` 关闭 stdin 后，LSP 服务器收到 EOF 会提前退出，
导致 initialize 响应在写入 stdout 之前就被丢弃。最终只能收到 shutdown 请求的
`"server not initialized"` 错误（因为 initialize 尚未完成时 shutdown 就被处理了）。

这是一个**时序竞争问题**: 批量写入时，LSP 服务器同时收到所有消息，但处理 initialize
是异步的，而 exit 通知立即触发进程退出。

### 修复

将 `probeLspServer()` 改为使用 `globalLspSession.ensureInitialized()` 持久化会话管理器。
该管理器已实现交互式帧读写：发送 initialize → 逐帧读取直到收到 id 匹配的响应 → 发送 initialized。
完美解决了时序竞争问题。

同时将 `LspSessionManager.ensureInitialized()` 的可见性从 `func` 改为 `public func`，
使其可以被 `probeLspServer()` 直接调用。

注意: `runLspSession()` 的冷启动批量发送方式仍保留作为 `runLspRequestColdStart()` 的兜底，
但主查询路径 `runLspRequest()` 已优先使用持久化会话，所以此问题对主流程无影响。

---

## 问题 6：Agent E2E 测试环境依赖

### 现象

`stdioMcpCanBootstrapCreateFileAndValidateProject` 测试始终失败（约 2 秒超时）。

### 分析

该测试是 agent 包的端到端测试，会：
1. 创建临时工作区
2. 启动 MCP service 进程
3. 调用 `project.bootstrap_json_parser` 生成项目
4. 调用 `workspace.run_build` 和 `workspace.run_test` 构建并测试生成的项目

测试失败原因是临时工作区中 `cjpm` 编译工具不可用或 SDK 环境变量未传递到子进程。这是测试环境配置问题，不是代码缺陷。
