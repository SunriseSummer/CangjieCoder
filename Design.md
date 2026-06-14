# 技术设计

## 架构总览

```
                       ┌──────────────────────────────┐
                       │            REPL              │
                       │  /chat /mode /diff /undo …   │
                       └──────────────┬───────────────┘
                                      │
                ┌─────────────────────┼─────────────────────┐
                ▼                                           ▼
        ┌───────────────┐                           ┌────────────────┐
        │   AgentLoop   │  (多轮工具调用)            │   ChatSession  │  (单轮流式)
        └──────┬────────┘                           └────────┬───────┘
               │                                             │
               │ IChatClient.sendForMessage()                │ ChatClient.send() (SSE)
               ▼                                             ▼
        ┌──────────────────────────────────────────────────────────┐
        │                ChatRequest / ChatMessage                 │
        │  + ToolSpec + ToolCall + tool_choice="auto"              │
        └──────────────────────────┬───────────────────────────────┘
                                   │ HTTPS (Bearer auth)
                                   ▼
                ┌─────────────────────────────────────────┐
                │  OpenAI-compatible /chat/completions    │
                └─────────────────────────────────────────┘
                                   │
                                   ▼
                            (tool_calls)
                                   │
        ┌──────────────────────────┴────────────────────────────────┐
        ▼                                                           ▼
┌────────────────┐                                          ┌──────────────────┐
│  ToolRegistry  │  ────►  9 内置工具 + Approver            │   FileJournal    │
│  (name → Tool) │                                          │  (快照栈)         │
└────────────────┘                                          └──────────────────┘
```

代码按职责划分为 8 个包：

| 包 | 职责 |
| --- | --- |
| `app` | 入口、Bootstrap、REPL 主循环 |
| `commands` | 斜杠命令分发与处理 |
| `agent` | AgentLoop、Approver、系统提示组装 |
| `tools` | Tool 接口、ToolRegistry、9 个内置工具、FileJournal、TodoStore、共享工具函数（`truncateWithEllipsis`/`truncateHeadTail`/`walkDir`） |
| `httpx` | ChatRequest/ChatMessage 序列化、流式与非流式 HTTP 客户端、工具调用解析 |
| `provider` | 5 个服务商预设（endpoint、模型列表） |
| `config` | 配置文件加载与持久化 |
| `session` | 单轮聊天的 history 管理 |

## 核心流程

### Agent Loop

经典 ReAct 循环（`agent/loop.cj`），每轮：

1. 将 history 与系统提示组装为 `ChatRequest`
2. 非流式调用 `IChatClient.sendForMessage()`，得到 `(content, toolCalls, reasoningContent)`
3. 若存在 `toolCalls`：
   - 将 `assistant(content + tool_calls + reasoningContent)` 写入 history
   - 逐个执行工具（经 Approver 审批），每个结果作为 `role:"tool"` 消息追加
   - 进入下一轮
4. 若无 `toolCalls`：
   - 将 `assistant(content)` 写入 history，作为最终答复返回
5. `maxIterations`（默认 50，可通过 `CANGJIECODER_MAX_ITERATIONS` 配置）兜底防死循环

`AgentLoop` 依赖 `IChatClient` 接口而非具体实现，E2E 测试可注入 mock。

### 思考模型支持

部分模型（kimi-k2.6、DeepSeek R1）在 assistant 消息中返回 `reasoning_content` 字段。API 要求后续请求必须携带该字段。`ChatMessage.reasoningContent` 在解析响应时捕获，序列化请求时回传。

### 工具执行与审批

单次工具执行流程（`agent/execute.cj`）：

```
ToolCall → ToolRegistry.get(name) → Approver.confirm() → Tool.execute(argsJson) → ToolResult
```

审批三档策略（`agent/approval.cj`）：

| 策略 | 行为 |
| --- | --- |
| `auto` | 全部放行 |
| `default` | safe 工具放行；sensitive 工具弹 `y/n/a` 确认，`a` 升级为 auto |
| `readonly` | safe 工具放行；sensitive 工具拒绝，拒绝原因塞回 `role:tool` 供模型换路径 |

工具的安全级别由 `Tool.approval: ApprovalLevel` 静态声明。

## 核心算法

### 文件变更日志

`FileJournal`（`tools/file_journal.cj`）实现栈式变更追踪：

- `edit_file` / `write_file` 执行前调用 `FileJournal.record(path, tool)`，将原始字节与文件是否存在入栈
- `/diff`：遍历全栈，按文件去重，输出起点到当前的字节变化量
- `/undo`：出栈一条记录恢复磁盘——若文件原本不存在则删除，否则回写原始字节

栈式设计支持连续 `/undo`，可回滚到会话开始时的磁盘状态。

### 历史压缩

`/compact`（`commands/compact.cj`）为纯本地确定性算法，不依赖 LLM：

1. 始终保留首条 user 消息（任务定义）与最近 N 条消息（默认 6 条）
2. 中间被丢弃的消息折叠为一条合成提示，包含统计摘要（跳过消息数、工具调用次数等）
3. `alignToBlockBoundary` 将 tail 起点对齐到 `assistant(tool_calls) + tool(...)` 块边界，确保不破坏 OpenAI 协议约束（assistant 携 tool_calls 后必须紧跟同 id 的 tool 响应）

### 系统提示组装

`agent/prompt.cj` 按以下顺序拼装 system prompt：

1. Agent 人设（AGENT_PERSONA）
2. 工具使用指引
3. 项目概览（顶层文件树、README.md / AGENTS.md 摘要）
4. 用户自定义 base prompt

### 工具协议

所有工具实现统一接口：

```cangjie
public interface Tool {
    prop name: String
    prop description: String
    prop parametersSchemaJson: String   // JSON Schema
    prop approval: ApprovalLevel
    func execute(argsJson: String): ToolResult
}
```

`ToolResult` 为 `ok(content)` 或 `err(message)` 二元结构，工具失败返回错误而非抛异常，供模型自行调整策略。

### HTTP 客户端

`httpx/client.cj` 实现：

- 基于 stdx 的 HTTPS 客户端，Bearer 认证
- `send`（SSE 流式）与 `sendForMessage`（非流式）通过 `executeRequest` 共享 HTTP 客户端构建与请求发送逻辑
- TLS 证书加载：探测 `SYSTEM_CA_PATHS` 常量定义的 5 种发行版 CA bundle 路径（可通过 `--ca-bundle` 覆盖），`X509Certificate.decodeFromPem` 解析后注入 `CertificateVerifyMode.CustomCA`
- 瞬态错误重试（3 次指数退避）
- UTF-8 安全的响应体读取（先读 raw bytes 再 `String.fromUtf8()`，避免 chunked transfer 切分多字节字符）

### 关键防御措施

| 问题 | 原因 | 对策 |
| --- | --- | --- |
| 多行 raw-string 带额外双引号 | `##"""..."""##` 定界符为 `##"` / `"##`，内容首尾各含 `""` | `sanitizeSchemaJson` 归一化到首个 `{` 与末尾 `}` |
| stdout 块缓冲 | glibc 在 pipe 下对 stdout 采用块缓冲 | REPL 每次 prompt 和输出后显式 `flush()` |
| UTF-8 截断崩溃 | 字节级 `s[..max]` 切分 CJK 多字节字符 | 全局使用 `truncateUtf8` 安全截断，`truncateWithEllipsis`/`truncateHeadTail` 提供统一截断 API |
| TLS SNI 缺失 | stdx 1.0.5 HTTP Client 不自动发送 SNI | `buildHttpClient` 从 URL 提取 hostname 显式设置 `tls.domain` |

## 测试体系

| 层级 | 工具 | 入口 |
| --- | --- | --- |
| 单元测试 | `std.unittest` | `cjpm test` |
| Mock E2E | Python subprocess | `e2etest/run_all.py --mock-only` |
| 实战 E2E | Python subprocess | `e2etest/run_all.py --provider <id>` |
| 烟雾测试 | Python unittest | `e2etest/test_*_smoke.py` |

Mock E2E 基于 Python stdlib 实现的本地 OpenAI 模拟服务端，可编排任意 tool-call 场景，覆盖 AgentLoop、FileJournal、`/diff`、`/undo`、`/compact` 等完整路径。

实战 E2E 通过 `--provider`/`--model` CLI 参数在框架层面切换服务商，使用 coder 的 `/connect` 和 `/model` 命令完成端到端配置。
