# CangjieCoder 扩展开发与重构优化记录

## 一、项目架构概述

CangjieCoder 是一个基于仓颉语言的 AI 编程助手，由两个核心模块组成：

- **service**（底层能力服务）：MCP Server，提供文件读写、AST 编辑、受限命令执行、LSP 查询等能力
- **agent**（智能体）：维护多轮对话（ReAct 循环），与 LLM 交互，生成计划并解析执行

## 二、本次优化内容

### 2.1 Token 感知的上下文管理（Issue #1）

**问题**：原有方案按固定轮次（12 轮）截断会话，未考虑单轮 token 长度，容易导致上下文溢出。

**优化**：
- 新增 `estimateTokenCount()` 函数，以 `bytes/3` 近似估算 token 数（英文 ~4 字符/token，中文 ~2 字符/token 的折中）
- 新增 `TOKEN_BUDGET = 8000` 常量，远小于主流模型窗口，预留系统提示和工具描述空间
- `ConversationSession.addTurn()` 中调用 `trimToTokenBudget()` 执行智能截断：
  - 先按 `CONVERSATION_TURN_LIMIT` 硬上限兜底
  - 再按 token 预算淘汰最旧对话，保证最近交互上下文完整
  - 至少保留 1 轮对话避免空上下文

**涉及文件**：`agent/src/ai_core.cj`

### 2.2 紧凑工作区上下文注入（Issue #2）

**问题**：每轮规划时将完整的 `workspaceSnapshot` JSON 注入 Prompt，对中大型项目极度浪费 token。

**优化**：
- 新增 `buildCompactWorkspaceSummary()` 函数，从 workspace 快照中提取关键信息：
  - 文件总数
  - 关键文件（`cjpm.toml`、`main.cj`、`README.md`）
  - 顶层目录结构
  - 非测试源码文件列表
- `buildPlanPrompt()` 和 `buildReplanPrompt()` 使用紧凑摘要替代全量 JSON
- 提取共用规则为 `PLAN_EXPLORE_RULE` 常量，避免重复维护

**涉及文件**：`agent/src/planner/prompts.cj`

### 2.3 LSP 持久化长连接（Issue #3）

**问题**：原实现每次 LSP 查询都冷启动进程（启动 → initialize → 查询 → shutdown → 退出），完全丧失了 LSP 协议的性能优势。

**优化**：
- 新增 `readLspFrameFromStream()` 函数，支持从子进程 stdout 逐字节读取 LSP Content-Length 帧
- 新增 `LspSessionManager` 类，维护长驻 LSP 子进程：
  - `ensureInitialized()` —— 首次使用时执行 initialize 握手，后续查询复用
  - `query()` —— 通过已初始化的进程发送请求，按 id 匹配响应，自动跳过通知帧
  - `close()` —— 发送 shutdown/exit 协议消息后强制终止进程
  - `isResponseWithId()` —— 结构化的 JSON-RPC 响应 id 匹配
- 全局 `globalLspSession` 被所有 LSP 查询复用
- `runLspRequest()` 入口优先走持久化会话，失败时自动回退到冷启动
- 保留 `runLspRequestColdStart()` 作为兜底，确保稳定性
- LSP 命令路径缓存（`lspCommandCache`）避免重复的文件系统和 PATH 探测

**涉及文件**：`service/src/lsp/session.cj`、`service/src/lsp/queries.cj`

### 2.4 健壮的 JSON 提取（Issue #4）

**问题**：原 `extractJsonObjectText()` 仅通过首个 `{` 和最后一个 `}` 截取，遇到多 JSON 块或代码示例中的花括号即崩溃。

**优化**：
- 重写 `extractJsonObjectText()` 使用括号深度追踪：
  - 正确处理字符串内部花括号（`"text with { braces }"`）
  - 正确处理转义字符（`\"` 不中断字符串状态）
  - 支持 Markdown 代码围栏内的 JSON 提取
  - 提取所有候选 `{...}` 对象
  - 优先选择包含 `steps`/`summary` 字段的 JSON（plan 格式）
  - 每个候选通过 `JsonValue.fromStr()` 验证合法性
  - 无合法候选时返回空字符串（优雅降级）

**涉及文件**：`agent/src/planner/json.cj`

### 2.5 事务回滚机制（Issue #5）

**问题**：文件修改操作直接原地覆盖，模型规划出错或 AST 替换破坏语法后无法恢复。

**优化**：
- 新增 `FileBackupStore` 类，实现文件级事务回滚：
  - `backup(path)` —— 首次修改前保存文件原始内容
  - `rollbackAll()` —— 一键恢复所有已备份文件
  - `clear()` —— 清空备份状态
  - `hasBackups()` / `fileCount` —— 查询备份状态
- 全局 `globalBackupStore` 供所有 MCP 工具共享
- 自动集成到所有变更操作：
  - `replaceExactText()` —— 文本替换前备份
  - `workspaceCreateFileJson()` —— 覆盖创建前备份
  - `handleEditAstNode()` —— AST 编辑前备份
- 新增 `workspace.rollback` MCP 工具，供 Agent 或用户显式触发回滚

**涉及文件**：`service/src/core.cj`、`service/src/mcp_server.cj`、`service/src/mcp_protocol.cj`、`service/src/workspace_tools.cj`

### 2.6 会话持久化（Issue #6）

**问题**：`ConversationStore` 仅存于内存，进程退出后所有上下文丢失，不支持任务恢复。

**优化**：
- `ConversationStore.saveToFile(path)` —— 将所有会话序列化为 JSON 写入文件
- `ConversationStore.loadFromFile(path)` —— 从 JSON 文件恢复会话状态
  - 文件不存在时静默跳过
  - 文件损坏时静默忽略，从空状态重新开始
  - 反序列化逻辑拆分为 `deserializeSessionTurns()` 和 `deserializeSessions()` 辅助函数，降低圈复杂度

**涉及文件**：`agent/src/ai_core.cj`

### 2.7 圈复杂度优化

**问题**：多个核心函数嵌套层级过深（4-5 级），圈复杂度高，可维护性差。

**优化**：

| 函数 | 文件 | 优化措施 |
|------|------|----------|
| `loadFromFile` | `ai_core.cj` | 提取 `deserializeSessionTurns()` 和 `deserializeSessions()`，嵌套从 5 级降至 3 级 |
| `probeLspServer` | `lsp/queries.cj` | 提取 `isSuccessfulInitializeResponse()` 和 `findSuccessfulProbeResponse()` |
| `runAgent` | `runner.cj` | 提取 `executeRoundSteps()` 和 `generateFinalReport()`，消除工具执行循环和最终报告的内联逻辑 |
| `buildFallbackPlan` | `planner/planning.cj` | 提取 `isNewProjectRequest()`，将 6 条件的项目检测逻辑分离 |

## 三、测试覆盖

本次新增 21 个单元测试，总计 69 个测试全部通过：

| 测试类别 | 新增数 | 测试内容 |
|----------|--------|----------|
| Token 估算 | 2 | 空串返回 0、英文近似值合理 |
| Token 预算截断 | 2 | 大量内容触发截断、至少保留 1 轮 |
| 会话持久化 | 3 | 保存/加载往返、损坏文件容错、缺失文件容错 |
| JSON 提取 | 4 | 多块优先 steps、字符串内花括号、尾部花括号、纯文本返回空 |
| 紧凑摘要 | 2 | 提取关键信息、空快照处理 |
| 文件备份/回滚 | 3 | 备份恢复、仅首次备份、清空状态 |
| 替换备份集成 | 1 | `replaceExactText` 自动创建备份 |
| LSP 缓存 | 1 | 缓存命中/清除/刷新 |
| MCP 回滚工具 | 3 | 运行时回滚恢复、无备份报告空、工具注册 |

## 四、LSP 连接模型说明

**当前状态**：已实现**持久化长连接**。

LSP 连接经历了两个阶段：

1. **冷启动模式（原有）**：每次查询启动新进程 → initialize → 查询 → shutdown → 退出。延迟高，CPU 开销大。
2. **长驻模式（当前）**：`LspSessionManager` 维护一个全局长驻子进程，首次使用时完成 initialize 握手，后续查询复用该进程。当会话异常时自动回退到冷启动模式保证可用性。

长连接的优势：
- 避免每次查询的进程启动和 initialize 握手开销
- 复用 LSP Server 内部的语义缓存（AST、类型信息等）
- 显著提升 `document-symbols` 和 `definition` 的响应速度

回退机制：
- 持久化会话初始化失败 → 自动回退到冷启动
- 进程崩溃或流关闭 → 标记会话失效，下次查询重新初始化
- `closeLspSession()` 和 `clearLspCommandCache()` 供测试和环境变更使用

## 五、子包拆分

### 5.1 LSP 子包（`cangjiecoder.lsp`）

将原 `service/src/lsp.cj`（655 行）拆分为 `service/src/lsp/` 子包：

| 文件 | 职责 |
|------|------|
| `protocol.cj` | 类型定义（LspStatus/LspProbeResult/LspQueryResult）、协议常量、帧编解码、消息构建、响应分类 |
| `session.cj` | LspSessionManager 长驻会话管理、命令发现与缓存、帧流读取 |
| `queries.cj` | 高层查询接口（document symbols/workspace symbols/definition）、冷启动回退、LSP 探测 |

所有外部可见的类型和函数标记为 `public`，根包通过 `import cangjiecoder.lsp.*` 使用。子包内部复制了少量工具函数（`lspShortPreview`、`lspReadTextFile`、`lspEnsureWorkspacePath`、`lspRunCommand`）以避免对根包的循环依赖。

### 5.2 Agent 共享类型子包（`cangjiecoderagent.common`）

将原 `agent/src/agent_core.cj` 中的共享类型和工具函数拆分为 `agent/src/common/` 子包：

| 文件 | 职责 |
|------|------|
| `types.cj` | AgentConfig、PlannedToolCall、AgentPlan、ToolExecution、ModelTurn、AgentPlanningContext、MAX_PLAN_STEPS |
| `helpers.cj` | jsonField、parseJsonObject、shortPreview、extractStructuredData、jsonArrayStrings、containsAny、shellQuote |

根包和 planner 子包都通过 `import cangjiecoderagent.common.*` 使用这些共享定义。

### 5.3 规划器子包（`cangjiecoderagent.planner`）

将原 `agent/src/planner.cj`（537 行）拆分为 `agent/src/planner/` 子包：

| 文件 | 职责 |
|------|------|
| `json.cj` | extractJsonObjectText — 深度追踪 JSON 提取 |
| `prompts.cj` | buildPlanPrompt、buildReplanPrompt、buildCompactWorkspaceSummary — 提示词构建 |
| `planning.cj` | parsePlan、buildFallbackPlan、normalizePlanSteps — 计划解析与回退逻辑 |

### 5.4 MCP 子包（`cangjiecoder.mcp`）

MCP 模块采用**协议/处理分离**的架构：

- **`mcp/protocol.cj`**（子包）：仅包含协议层代码 —— ToolArgSpec/ToolDefinition 类型、工具定义列表、JSON-RPC 响应构建、mcpToolCallResultJson、stdio 帧编解码
- **`mcp_handlers.cj`**（根包）：MCP 工具处理函数、McpRuntime、工具/方法注册表、stdio 服务入口、createMcpRuntime 工厂函数

| 文件 | 位置 | 职责 |
|------|------|------|
| `mcp/protocol.cj` | 子包 | ToolArgSpec/ToolDefinition、buildToolDefinitions、toolDefinitionsJson、jsonRpcResult/jsonRpcError、mcpToolCallResultJson、encodeMcpFrame/readStdioFrame |
| `mcp_handlers.cj` | 根包 | McpToolContext、所有 handle* 处理函数、buildMcpToolRegistry/buildMcpMethodRegistry、McpRuntime、startMcpStdioServer、createMcpRuntime |

**设计决策**：处理函数直接调用根包域函数（`replaceExactText`、`workspaceListFilesJson`、LSP 查询等），无需函数引用桥接。协议类型和帧编解码放在子包中保持关注分离，而处理逻辑自然属于根包（它需要所有域函数的直接访问）。

## 六、文件变更清单

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `agent/src/ai_core.cj` | 修改 | Token 预算、会话持久化、反序列化重构 |
| `agent/src/agent_core.cj` | 修改 | 移除迁入 common 子包的类型和函数 |
| `agent/src/common/types.cj` | 新增 | 共享类型定义子包 |
| `agent/src/common/helpers.cj` | 新增 | 共享工具函数子包 |
| `agent/src/planner/json.cj` | 新增 | JSON 提取（从 planner.cj 拆出） |
| `agent/src/planner/prompts.cj` | 新增 | 提示词构建（从 planner.cj 拆出） |
| `agent/src/planner/planning.cj` | 新增 | 计划解析与回退（从 planner.cj 拆出） |
| `agent/src/runner.cj` | 修改 | 提取 executeRoundSteps、generateFinalReport |
| `agent/src/ai_core_test.cj` | 修改 | 新增 7 个测试 |
| `agent/src/agent_test.cj` | 修改 | 新增 6 个测试 |
| `service/src/core.cj` | 修改 | FileBackupStore、globalBackupStore |
| `service/src/lsp/protocol.cj` | 新增 | LSP 协议层（从 lsp.cj 拆出） |
| `service/src/lsp/session.cj` | 新增 | LSP 会话管理（从 lsp.cj 拆出） |
| `service/src/lsp/queries.cj` | 新增 | LSP 查询接口（从 lsp.cj 拆出） |
| `service/src/mcp/protocol.cj` | 新增 | MCP 协议层 — 工具定义、JSON-RPC 辅助、帧编解码 |
| `service/src/mcp_handlers.cj` | 新增 | MCP 工具处理、运行时、注册表、stdio 服务、createMcpRuntime |
| `service/src/json_helpers.cj` | 修改 | 移除已迁入 MCP 子包的 JSON-RPC 辅助函数 |
| `service/src/workspace_tools.cj` | 修改 | 自动备份集成 |
| `service/src/skills_test.cj` | 修改 | 备份回滚和 LSP 缓存测试 |
| `service/src/server_test.cj` | 修改 | MCP 回滚工具集成测试 |
| `service/src/mcp_protocol_test.cj` | 修改 | 工具注册覆盖测试 |
| `service/src/projects_test.cj` | 修改 | LSP 测试清理全局状态 |
| `record.md` | 新增 | 本文档 |
