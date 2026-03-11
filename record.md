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

## 三、tree-sitter 内置 AST 服务

### 3.1 cangjie-tree-sitter 独立库

将 tree-sitter 引擎封装为独立的仓颉项目 `cangjie-tree-sitter/`（输出动态库），类似 Rust / Python 等主流语言的 tree-sitter 绑定做法：

**项目结构**：
```text
cangjie-tree-sitter/
├── cjpm.toml           # output-type = "dynamic"，包名 cjtreesitter
├── src/
│   ├── treesitter.cj       # FFI 声明 + 公共 API
│   └── treesitter_test.cj  # 10 个单元测试
└── treesitter/             # C 源码
    ├── Makefile            # 编译 libtree_sitter_cangjie.so
    ├── ts_lib.c            # tree-sitter 运行时 v0.25.3
    ├── cangjie_parser.c    # CangjieTreeSitter 1.0.5.2 语法
    ├── cangjie_scanner.c   # CangjieTreeSitter 外部扫描器
    └── ...                 # tree-sitter 内部头文件和源文件
```

**C FFI 层**：
- `@C struct TSPoint`/`TSNode`/`TSTreeCursor` —— 与 tree-sitter C API 结构体一一映射
- `foreign` 块声明 20+ 个 tree-sitter 核心函数（parser 生命周期、节点遍历、游标操作等）
- 内存管理正确配对：`ts_parser_new()`/`ts_parser_delete()`、`acquireArrayRawData()`/`releaseArrayRawData()`、`free()` 释放 `ts_node_string()` 返回的 C 字符串

**公共 API**（所有函数支持可选 `language!` 参数，默认使用 `cangjieLanguage()`）：

| 函数 | 说明 |
|------|------|
| `cangjieLanguage()` | 返回内置仓颉语法的 `CPointer<Unit>` |
| `parseSexp(source, language!)` | 解析源码并返回 S-expression 字符串 |
| `parseRootInfo(source, language!)` | 解析并返回根节点的 `NodeInfo` |
| `queryNodes(source, nodeType, language!)` | 递归查询指定类型的所有节点 |
| `listNamedNodes(source, maxDepth!, language!)` | 收集命名节点概览（限制深度） |
| `nodeInfoToJson(node)` | 单个 `NodeInfo` 序列化为 JSON |
| `nodeInfoArrayToJson(nodes)` | `NodeInfo` 数组序列化为 JSON |

**多语言插件设计**：库默认集成 Cangjie 语法插件，但也支持接入其他语言的 tree-sitter 语法插件。只需传入不同的 `language!` 参数（由外部 tree-sitter 语法库提供的 `CPointer<Unit>`），即可复用同一套解析 API。

### 3.2 service 集成

`service` 通过 `[dependencies] cjtreesitter = { path = "../cangjie-tree-sitter" }` 依赖该库，`service/src/ast/ast.cj` 作为薄代理层（零 unsafe 代码）：
- 类型别名 `AstNodeInfo = NodeInfo`
- 代理函数 `treeSitterParseSexp()` / `treeSitterQueryNodes()` / `treeSitterListNamedNodes()` 等

新增 3 个 MCP 工具：

| 工具名 | 功能 |
|--------|------|
| `cangjie.ast_parse` | 解析仓颉源码，返回完整 S-expression AST |
| `cangjie.ast_query_nodes` | 按节点类型查询所有匹配节点及位置信息 |
| `cangjie.ast_list_nodes` | 列出命名 AST 节点概览（可配置深度） |

### 3.3 与现有 AST 编辑的关系

- `cangjie.edit_ast_node` 和 `cangjie.analyze_file` 仍依赖**外部** tree-sitter CLI（通过 `$TREE_SITTER_CANGJIE` 环境变量）
- `cangjie.ast_parse`/`cangjie.ast_query_nodes`/`cangjie.ast_list_nodes` 使用**内置** tree-sitter（通过 `cangjie-tree-sitter` 库），无需外部工具

### 3.4 workspace 更新

根目录 `cjpm.toml` 更新为 3 成员 workspace：

```toml
[workspace]
members = ["cangjie-tree-sitter", "service", "agent"]
build-members = ["cangjie-tree-sitter", "service", "agent"]
test-members = ["cangjie-tree-sitter", "service", "agent"]
```

### 3.5 测试覆盖

新增 23 个测试用例，总计 92 个测试全部通过：

| 测试类别 | 数量 | 位置 | 测试内容 |
|----------|------|------|----------|
| 库单元测试 | 10 | `cangjie-tree-sitter` | S-expression 解析、空源码处理、根节点类型、节点类型查询、无匹配空结果、命名节点列举、JSON 序列化、语言接口非空、显式语言参数 |
| 服务单元测试 | 8 | `service` | 通过代理层的 S-expression 解析、根节点类型、节点查询、JSON 序列化 |
| MCP 集成测试 | 5 | `service` | AST 解析工具调用、节点查询工具调用、节点列举工具调用、工具注册表覆盖、工具定义包含 AST 工具 |

## 四、测试覆盖

本次新增 44 个单元测试（含 tree-sitter 库 10 + tree-sitter service 集成 13 + 原有 21），总计 92 个测试全部通过：

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

## 五、LSP 连接模型说明

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

## 六、子包拆分

### 6.1 服务共享子包（`cangjiecoder.common`）

将核心类型和工具函数提取到 `service/src/common/`：

| 文件 | 职责 |
|------|------|
| `types.cj` | AppConfig、APP_VERSION — 应用配置和版本常量 |
| `helpers.cj` | 路径处理（resolveBundledPath/resolveRepoPath/ensureWorkspacePath/workspaceRelativePath）、文件读写（readTextFile/writeTextFile）、文本预览（shortPreview）、命令执行（runCommandDetailedOutput/runCommandWithCapturedOutput） |

### 6.2 JSON 工具子包（`cangjiecoder.json`）

将通用 JSON 解析/序列化工具提取到 `service/src/json/`：

| 文件 | 职责 |
|------|------|
| `helpers.cj` | jsonField、parseJsonObject、parseJsonIntField、parseJsonBoolField、jsonStringArrayField、toolResultJson、toolMessageJson、toolCommandResultJson |

### 6.3 技能子包（`cangjiecoder.skills`）

将技能注册表逻辑提取到 `service/src/skills/`：

| 文件 | 职责 |
|------|------|
| `registry.cj` | SkillRecord 类型、SkillRegistry 类（加载/搜索/排名/上下文构建）、scoreSkill、parseSkill |

### 6.4 项目模板子包（`cangjiecoder.projects`）

将项目模板管理逻辑提取到 `service/src/projects/`：

| 文件 | 职责 |
|------|------|
| `templates.cj` | ExampleProjectSpec 类型、listExampleProjects、findExampleProject、ensurePlannedWorkspacePath、bootstrapJsonParserProject |

### 6.5 代码分析子包（`cangjiecoder.analysis`）

将 AST 编辑和代码分析逻辑提取到 `service/src/analysis/`：

| 文件 | 职责 |
|------|------|
| `analyzer.cj` | AstNodeMatch/AnalysisResult 类型、AST 解析（parseTreeSitterNodeMatches/offsetForPoint）、editAstNode、astEditSucceeded、analyzeCangjieFile |

### 6.6 LSP 子包（`cangjiecoder.lsp`）

将原 `service/src/lsp.cj`（655 行）拆分为 `service/src/lsp/` 子包：

| 文件 | 职责 |
|------|------|
| `protocol.cj` | 类型定义（LspStatus/LspProbeResult/LspQueryResult）、协议常量、帧编解码、消息构建、响应分类 |
| `session.cj` | LspSessionManager 长驻会话管理、命令发现与缓存、帧流读取 |
| `queries.cj` | 高层查询接口（document symbols/workspace symbols/definition）、冷启动回退、LSP 探测 |

### 6.7 MCP 子包（`cangjiecoder.mcp`）

MCP 模块采用**协议/处理分离**的架构：

| 文件 | 位置 | 职责 |
|------|------|------|
| `mcp/protocol.cj` | 子包 | ToolArgSpec/ToolDefinition、buildToolDefinitions、toolDefinitionsJson、jsonRpcResult/jsonRpcError、mcpToolCallResultJson、encodeMcpFrame/readStdioFrame |
| `mcp_handlers.cj` | 根包 | McpToolContext、所有 handle* 处理函数、buildMcpToolRegistry/buildMcpMethodRegistry、McpRuntime、startMcpStdioServer、createMcpRuntime |

### 6.8 Agent 共享类型子包（`cangjiecoderagent.common`）

将共享类型和工具函数提取到 `agent/src/common/`：

| 文件 | 职责 |
|------|------|
| `types.cj` | AgentConfig、PlannedToolCall、AgentPlan、ToolExecution、ModelTurn、AgentPlanningContext、MAX_PLAN_STEPS |
| `helpers.cj` | jsonField、parseJsonObject、shortPreview、extractStructuredData、jsonArrayStrings、containsAny、shellQuote |

### 6.9 AI 对话子包（`cangjiecoderagent.ai`）

将 AI 对话管理和提供者逻辑提取到 `agent/src/ai/`：

| 文件 | 职责 |
|------|------|
| `conversation.cj` | ConversationTurn/ConversationSession/ConversationStore — 会话管理、token 预算截断、持久化序列化/反序列化 |
| `providers.cj` | ProviderSpec — 提供者配置、API 调用（chatWithProvider）、响应解析、系统提示词、conversationTurn |

### 6.10 MCP 客户端子包（`cangjiecoderagent.client`）

将 MCP 客户端通信逻辑提取到 `agent/src/client/`：

| 文件 | 职责 |
|------|------|
| `service_client.cj` | ServiceClient 类（MCP stdio 调用）、帧编解码（encodeMcpFrame/extractMcpBodies）、JSON-RPC 请求构建、服务命令解析 |

### 6.11 规划器子包（`cangjiecoderagent.planner`）

将规划逻辑提取到 `agent/src/planner/`：

| 文件 | 职责 |
|------|------|
| `json.cj` | extractJsonObjectText — 深度追踪 JSON 提取 |
| `prompts.cj` | buildPlanPrompt、buildReplanPrompt、buildCompactWorkspaceSummary — 提示词构建 |
| `planning.cj` | parsePlan、buildFallbackPlan、normalizePlanSteps — 计划解析与回退逻辑 |

### 6.12 AST 服务子包（`cangjiecoder.ast`）

`service/src/ast/ast.cj` 作为 `cangjie-tree-sitter` 库的薄代理：

| 文件 | 职责 |
|------|------|
| `ast.cj` | 类型别名 `AstNodeInfo = NodeInfo`、代理函数 `treeSitterParseSexp`/`treeSitterQueryNodes`/`treeSitterListNamedNodes`/`astNodeInfoToJson`/`astNodeInfoArrayToJson`，零 unsafe 代码 |

### 子包设计原则

1. **子包不导入父包**：仓颉 cjpm 约束子包不能循环依赖父包，需要的工具函数在子包内部复制
2. **协议/类型/纯函数放子包**：子包只包含无副作用的类型定义、协议编解码和纯函数
3. **处理/业务逻辑留根包**：需要调用多个域函数的处理逻辑（MCP handlers）直接放在根包
4. **兄弟子包可互相导入**：`cangjiecoderagent.client` 可以导入 `cangjiecoderagent.common`

## 七、文件变更清单

### 服务端（service/src/）

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `common/types.cj` | 新增 | AppConfig、APP_VERSION — 共享配置和常量 |
| `common/helpers.cj` | 新增 | 路径处理、文件 I/O、命令执行 — 共享工具函数 |
| `json/helpers.cj` | 新增 | jsonField、parseJsonObject、工具结果序列化 — 通用 JSON 工具 |
| `skills/registry.cj` | 新增 | SkillRecord、SkillRegistry — 技能注册（从 skills.cj 拆出） |
| `projects/templates.cj` | 新增 | ExampleProjectSpec、项目引导 — 模板管理（从 projects.cj 拆出） |
| `analysis/analyzer.cj` | 新增 | AstNodeMatch、AnalysisResult、AST 编辑、代码分析（从 ast_edit.cj + workspace_tools.cj 拆出） |
| `lsp/protocol.cj` | 新增 | LSP 类型定义、协议常量、帧编解码 |
| `lsp/session.cj` | 新增 | LspSessionManager 长驻会话管理 |
| `lsp/queries.cj` | 新增 | LSP 高层查询接口、冷启动回退 |
| `mcp/protocol.cj` | 新增 | MCP 工具定义、JSON-RPC 辅助、帧编解码 |
| `ast/ast.cj` | 新增 | cangjie-tree-sitter 库的薄代理层，零 unsafe 代码 |
| `core.cj` | 修改 | 保留 FileBackupStore 和 replaceExactText，其余迁入子包 |
| `json_helpers.cj` | 修改 | 保留领域对象序列化（skillsJson/analysisJson/lspQueryJson 等），通用工具迁入 json 子包 |
| `workspace_tools.cj` | 修改 | 分析函数迁入 analysis 子包，保留工作区操作和命令执行 |
| `mcp_handlers.cj` | 修改 | MCP 处理函数、运行时、注册表 |
| `http_server.cj` | 删除 | HTTP 服务模块已移除，service 专注 MCP |
| `main.cj` | 修改 | 导入更新 |

### 智能体（agent/src/）

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `ai/conversation.cj` | 新增 | ConversationSession/Store、token 预算截断、持久化（从 ai_core.cj 拆出） |
| `ai/providers.cj` | 新增 | ProviderSpec、API 调用、系统提示词、conversationTurn（从 ai_core.cj 拆出） |
| `client/service_client.cj` | 新增 | ServiceClient、MCP 帧编解码、JSON-RPC 请求（从 mcp_client.cj 拆出） |
| `common/types.cj` | 新增 | AgentConfig、PlannedToolCall、AgentPlan、ModelTurn 等共享类型 |
| `common/helpers.cj` | 新增 | jsonField、parseJsonObject、shortPreview 等共享工具函数 |
| `planner/json.cj` | 新增 | extractJsonObjectText — 深度追踪 JSON 提取 |
| `planner/prompts.cj` | 新增 | 提示词构建 |
| `planner/planning.cj` | 新增 | 计划解析与回退逻辑 |
| `ai_core.cj` | 修改 | 功能迁入 ai 子包，保留包声明 |
| `mcp_client.cj` | 修改 | 功能迁入 client 子包，保留包声明 |
| `runner.cj` | 修改 | 导入更新 |
| `executor.cj` | 修改 | 导入更新 |
| `record.md` | 修改 | 更新本文档 |

### cangjie-tree-sitter 库

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `cjpm.toml` | 新增 | 动态库配置（output-type = "dynamic"），ffi.c 配置 |
| `src/treesitter.cj` | 新增 | C FFI 声明（TSPoint/TSNode/TSTreeCursor/20+ 函数）、公共 API（parseSexp/queryNodes/listNamedNodes 等）、JSON 序列化 |
| `src/treesitter_test.cj` | 新增 | 10 个单元测试 |
| `treesitter/Makefile` | 新增 | 编译 libtree_sitter_cangjie.so |
| `treesitter/*.c` | 新增 | tree-sitter 运行时 v0.25.3 + CangjieTreeSitter 1.0.5.2 语法 |

## 四、代码质量优化（Issue #7）

### 4.1 优化目标

对以下 6 个核心文件进行系统性代码质量优化：

- `service/src/analysis/analyzer.cj`
- `service/src/json/helpers.cj`
- `service/src/lsp/queries.cj`
- `service/src/lsp/session.cj`
- `service/src/mcp/protocol.cj`
- `service/src/mcp_handlers.cj`

### 4.2 优化内容

#### 4.2.1 降低圈复杂度

**`analyzer.cj` — analyzeCangjieFile 函数拆分**

原始 `analyzeCangjieFile()` 函数包含三级分析器的全部逻辑（tree-sitter → cjlint → cjc），每级都有成功/失败分支，圈复杂度高。

优化后拆分为三个独立的分析函数：
- `tryTreeSitterAnalysis()` — 尝试 tree-sitter 分析
- `tryCjlintAnalysis()` — 尝试 cjlint 静态检查
- `tryCjcAnalysis()` — 尝试 cjc 编译检查（兜底）

主函数通过 `if-let` 链式调用：
```cangjie
let treeSitterResult = tryTreeSitterAnalysis(fullPath, repoRoot)
if (let Some(result) <- treeSitterResult) { return result }
let lintResult = tryCjlintAnalysis(fullPath, repoRoot)
if (let Some(result) <- lintResult) { return result }
return tryCjcAnalysis(fullPath, repoRoot)
```

**`protocol.cj` — buildToolDefinitions 重构**

原始使用单个巨型数组字面量定义 22 个工具（超过 70 行嵌套），不便阅读和维护。

优化为 `ArrayList` 逐步构建模式，按工具类别分组添加，并在每组前添加分类注释：
```cangjie
let defs = ArrayList<ToolDefinition>()
// 技能检索
defs.add(ToolDefinition("skills.search", ...))
// 文件读写
defs.add(ToolDefinition("workspace.read_file", ...))
...
return defs.toArray()
```

**`json/helpers.cj` — parseJsonBoolField 简化**

移除了多余的 `raw.isEmpty()` 前置判断，因为空字符串既不等于 "true" 也不等于 "false"，最终都会走到 `return fallback` 分支。

#### 4.2.2 补充中文注释

为全部 6 个文件添加了系统性的中文注释，包括：

- **文件级注释**：描述模块职责、提供的核心能力、与其他模块的关系
- **代码分段标记**：使用 `// ── 段落名 ──` 风格清晰划分代码区域
- **函数级注释**：描述函数用途、参数含义、返回值语义、边界条件处理
- **关键逻辑注释**：在复杂分支、状态机转换、协议交互处添加行内注释

注释覆盖率从 ~30% 提升至 ~80%。

#### 4.2.3 代码规范性改进

- 统一了异常变量命名：将无用的 `catch (e: Exception)` 改为 `catch (_: Exception)`
- 在 `mcpToolCallResultJson()` 中简化了 `isError` 判定逻辑，从嵌套 match 改为直接比较
- 在 `mcp_handlers.cj` 中为 `McpRuntime` 类的成员变量添加了行内注释说明用途

### 4.3 新增测试用例

新增 `service/src/code_quality_test.cj` 测试文件，包含 5 个测试类、63 个测试用例：

| 测试类 | 测试数量 | 覆盖范围 |
|--------|----------|----------|
| `AnalyzerExtendedTest` | 12 | parseTreeSitterNodeMatches、offsetForPoint、sliceText、astEditSucceeded |
| `JsonHelpersExtendedTest` | 21 | jsonField、parseJsonObject、parseJsonIntField、parseJsonBoolField、jsonStringArrayField、toolResultJson、toolMessageJson、toolCommandResultJson |
| `LspProtocolExtendedTest` | 15 | LSP 帧编解码往返、findLspResponseById、lspResultToJsonValue、classifyLspResponse、buildLspInitializeParams、fileUri |
| `McpProtocolExtendedTest` | 12 | buildToolDefinitions 完整性/唯一性/描述检查、toolDefinitionsJson、jsonRpcResult/jsonRpcError、mcpToolCallResultJson、encodeMcpFrame |
| `McpHandlersExtendedTest` | 3 | 通知处理、连续请求、版本号验证 |

测试总数从 108 增加到 171，新增 63 个测试用例。

### 4.4 涉及文件

| 文件 | 变更类型 | 说明 |
|------|----------|------|
| `service/src/analysis/analyzer.cj` | 优化 | 拆分 analyzeCangjieFile 为三个子函数，补充完整中文注释 |
| `service/src/json/helpers.cj` | 优化 | 简化 parseJsonBoolField，补充完整中文注释 |
| `service/src/lsp/queries.cj` | 优化 | 补充完整中文注释和代码分段标记 |
| `service/src/lsp/session.cj` | 优化 | 补充完整中文注释，为 LspSessionManager 所有方法添加功能说明 |
| `service/src/mcp/protocol.cj` | 优化 | 重构 buildToolDefinitions 为 ArrayList 模式，补充完整中文注释 |
| `service/src/mcp_handlers.cj` | 优化 | 补充完整中文注释和代码分段标记 |
| `service/src/code_quality_test.cj` | 新增 | 63+1 个新增测试用例 |
| `record.md` | 更新 | 记录本次优化内容 |

## 五、异常处理机制优化

### 5.1 设计原则

1. **服务鲁棒性优先**：不造成阻断性影响的问题提供兜底机制，不终止服务
2. **Option 优先**：优先用 `Option<T>` 表达可失败操作，仅在必要时使用 `throw-try-catch`
3. **if-let 解构**：解构 Option 时优先用 `if-let` 而非 `match case`

### 5.2 消除的 throw 语句

项目中原有 13 处 `throw` 语句，全部改为返回 `Option` 或结构化错误结果：

| 函数 | 原始行为 | 优化后 |
|------|----------|--------|
| `parseNodeCoordinate` | throw 坐标解析失败 | 返回 `?((Int64,Int64),Int64)` |
| `offsetForPoint` | throw 坐标越界 | 返回 `?Int64` |
| `ensureWorkspacePath`（4 处副本） | throw 路径不存在/逃逸 | 返回 `?String` |
| `ensurePlannedWorkspacePath`（3 处 throw） | throw 父目录/逃逸 | 返回 `?String` |
| `LspSessionManager.sendFrame` | throw 进程未启动 | 返回 `Bool` |

### 5.3 if-let 解构模式

统一使用 `if-let` 替代 `match case` 解构 Option，主要模式：

**多条件组合（&&）**：
```cangjie
if (let Some(open) <- line.indexOf("[", fromIndex) &&
    let Some(comma) <- line.indexOf(",", open) &&
    let Some(close) <- line.indexOf("]", comma)) {
    // 三个索引同时有效时执行解析
}
```

**嵌套 if-let**：
```cangjie
if (let Some(fullPath) <- ensureWorkspacePath(repoRoot, path)) {
    // 路径有效时执行正常逻辑
    if (let Some(startOffset) <- offsetForPoint(current, ...) &&
        let Some(endOffset) <- offsetForPoint(current, ...)) {
        // 两个偏移都有效时执行替换
    }
}
return "错误兜底消息"
```

**简洁兜底（??）**：
```cangjie
return ensureWorkspacePath(repoRoot, path) ?? repoRoot
```

### 5.4 保留的 try-catch

以下场景保留 `try-catch` 作为最终安全网：

| 位置 | 原因 |
|------|------|
| `callMcpTool` | 顶层工具调度，防止任何未预期异常终止服务 |
| `McpRuntime.handleRequest` | 顶层请求处理，防止 JSON 解析异常 |
| `runLspRequestColdStart/probeLspServer` | LSP 子进程交互，防止 I/O 异常 |
| `analysisRunCommand/lspRunCommand` | 外部命令执行，防止进程启动失败 |
| `LspSessionManager.ensureInitialized/query` | 长驻进程状态管理，防止通信异常 |
| `FileBackupStore.rollbackAll` | 文件恢复，静默跳过单文件写入失败 |

### 5.5 涉及文件

| 文件 | 说明 |
|------|------|
| `service/src/common/helpers.cj` | `ensureWorkspacePath` → `?String` |
| `service/src/analysis/analyzer.cj` | `parseNodeCoordinate/offsetForPoint` → Option，`editAstNode/analyzeCangjieFile` 用 if-let |
| `service/src/lsp/queries.cj` | `lspEnsureWorkspacePath` → `?String`，查询函数用 if-let |
| `service/src/lsp/session.cj` | `sendFrame` → Bool，`resolveLspCommand/inspectLspStatus/ensureInitialized/query/close` 全部用 if-let |
| `service/src/projects/templates.cj` | `ensurePlannedWorkspacePath` → `?String`，`bootstrapJsonParserProject` 嵌套 if-let |
| `service/src/tools/workspace.cj` | 路径校验全部 if-let + ?? 兜底 |
| `service/src/tools/ast.cj` | AST 工具全部 if-let 兜底 |
| `service/src/code_quality_test.cj` | 适配 Option 返回值，新增越界测试 |
| `service/src/ast_edit_test.cj` | 适配 `offsetForPoint` 的 `?Int64` 返回 |

## 六、AST 与 Skills 服务增强

### 6.1 新增 tree-sitter 高层 API

**目标**：提供更高效的 AST 查询能力，让 AI 能精确提取代码片段而无需读取全文，大幅节省 Token。

**新增 API**：
- `extractNodeText(source, node)` — 从源码中按字节范围提取 AST 节点对应的原文
- `queryNodesWithText(source, nodeType)` — 查询匹配节点并同时返回源码文本
- `countNodes(source, nodeType)` — 轻量级节点计数，不提取完整信息
- `astSummary(source)` — 生成文本格式的文件结构摘要（顶层定义签名与行范围）
- `astSummaryJson(source)` — 生成 JSON 格式的结构化摘要条目

**涉及文件**：`cangjie-tree-sitter/src/treesitter.cj`

### 6.2 新增 MCP 工具（22 → 26）

| 工具名 | 说明 |
|--------|------|
| `cangjie.ast_summary` | 生成源文件结构摘要，列出函数/类/接口/结构体/枚举的签名与行范围 |
| `cangjie.ast_query_nodes_with_text` | 按节点类型查询并返回每个节点的源码文本 |
| `skills.batch_search` | 批量搜索多个技能查询，一次请求返回多组结果 |
| `skills.prompt_context` | 生成可直接嵌入 AI 提示词的技能上下文文本 |

**涉及文件**：
- `service/src/tools/ast.cj` — 新增 `handleAstSummary`、`handleAstQueryNodesWithText`
- `service/src/tools/skills.cj` — 新增 `handleSkillsBatchSearch`、`handleSkillsPromptContext`
- `service/src/tools/registry.cj` — 注册 4 个新工具
- `service/src/mcp/protocol.cj` — 添加 4 个工具定义（含参数规格与描述）

### 6.3 测试增强

**单元测试**（Cangjie）：新增 47 个测试用例，总计 219 个
- `TreeSitterEnhancedApiTest` — extractNodeText、queryNodesWithText、countNodes、astSummary/Json
- `AstToolsEnhancedTest` — ast_summary/query_nodes_with_text MCP 集成
- `SkillsToolsEnhancedTest` — batch_search/prompt_context MCP 集成、tools/list 验证
- `PracticalScenarioTest` — AI 实战场景（文件概览、函数查看、批量查找、两步探索）
- `SkillsRegistryEnhancedTest` — buildPromptContext、中英文混合查询、分词

**集成测试**（Python）：新增 41 个测试用例，总计 115 个
- `test_ast_enhanced.py` — 20 个测试：summary 格式验证、query_with_text 源码提取、summary+detail 组合工作流、工具列表验证
- `test_skills_enhanced.py` — 21 个测试：batch_search 多语言查询、prompt_context 限制验证、batch+context 组合工作流、工具总数验证

### 6.4 文档更新

- `mcp.md` — 更新工具总览表（22 → 26）、目录、概述；新增 4 个工具的详细文档（功能、原理、参数、示例）
- `service/README.md` — 更新工具列表表格，新增 4 个工具条目
- `record.md` — 新增第六章记录本次变更

## 七、移除内置模板体系，增强 Agent 开发策略

### 7.1 问题与动机

通过实际开发多个仓颉项目（JsonParser、TodoList、Calculator），发现内置模板引导方式并非必要——仓颉官方的 `cjpm init` 命令已经足以初始化新项目。内置模板增加了代码维护负担，且 Agent 不应依赖预制模板，而应具备基于 `cjpm init` + 技能文档自主创建任意项目的能力。

### 7.2 删除清单

**Service 层**：
- 删除 `service/src/projects/` 子包（`templates.cj`）
- 删除 `service/src/tools/project.cj`（工具处理函数）
- 删除 3 个 MCP 工具定义：`project.list_examples`、`project.bootstrap_json_parser`、`project.bootstrap`
- 删除 CLI 子命令：`examples`、`bootstrap-json-parser`、`bootstrap`
- 删除 `exampleProjectsJson()` 序列化函数
- 工具总数：26 → 24（后续若有需要，可通过 `cjpm init` 替代）
- `ensurePlannedWorkspacePath()` 迁移至 `cangjiecoder.common`（仍被 `workspace.create_file` 使用）

**Agent 层**：
- 从 `AgentPlanningContext` 中移除 `exampleProjectsJson` 字段
- 从 `runner.cj` 中移除 `project.list_examples` 调用
- 从 `executor.cj` 中移除 `project.bootstrap*` 的 mutating tool 判定
- 删除 `extractTargetPathFromPrompt()`、`detectExampleProjectId()` 等辅助函数

**模板文件**：
- 删除 `tests/json_parser/`、`tests/todo_list/`、`tests/calculator/`

**Python 集成测试**：
- 删除 `tests/test_project.py`（测试已移除的模板工具）
- 从 `tests/run_all.py` 中移除 `test_project` 模块

### 7.3 开发经验注入

将开发多个仓颉项目过程中总结的经验和最佳实践注入 Agent 提示词和规划策略中：

**仓颉语言关键注意事项**（注入 `prompts.cj` 提示词）：
- `Bool` 是关键字，不能用作 enum 变体名，需用 `JBool` 等前缀
- `Float64.parse()` 需要 `import std.convert.*`
- `for (ch in str)` 迭代 `UInt8` 字节而非 `Rune` 字符，应使用子串切片
- 优先使用 `Option<T>` + `if-let` 而非 `try-catch` 处理可恢复错误
- 代码变更后立即运行 `workspace.run_build` 捕获编译错误
- 编写代码前先用 `skills.search` 查阅语言特性文档
- 分析代码时先用 `cangjie.ast_summary` 获取概览，再用 `cangjie.ast_query_nodes` 定位具体节点

**Agent 规划策略增强**（注入 `planning.cj`）：
- 新建项目：检测到「新项目/新建/init」关键词时，使用 `workspace.run_command` 调用 `cjpm init`
- 特性查询：检测到语言特性关键词（JSON/HTTP/enum/class/泛型/接口等）时，优先调用 `skills.search`
- 提示词中不再引导模型使用 `project.bootstrap`，改为引导使用 `cjpm init`

### 7.4 新增测试

**Cangjie 单元测试**（`agent_test.cj`）：
- `fallbackPlanUsesRunCommandForNewProject` — 验证新建项目使用 `workspace.run_command`
- `fallbackPlanSearchesSkillsForFeatureQuestions` — 验证特性问题优先搜索技能文档
- `fallbackPlanInspectsCjpmTomlWhenPresent` — 验证工作区含 `cjpm.toml` 时自动读取
- `appendValidationStepsTreatsEditAstNodeAsMutation` — 验证 AST 编辑触发自动验证

**Python 集成测试**：
- `test_tools_inventory.py` — 29 个测试用例：验证 24 个工具全部存在、3 个已删除工具不存在、所有工具有描述
- `test_workspace_commands.py` — 新增 `run_command_cjpm_allowed` 验证 `cjpm` 在白名单中
- `test_skills_enhanced.py` — 工具总数断言更新为 24

**测试汇总**：217 个 Cangjie 测试 + 141 个 Python 集成测试全部通过

### 8. 动态工作区路径管理（Issue #8）

#### 8.1 问题分析

**原始问题**：MCP 服务启动时必须通过 `--repo` 参数指定目标仓库工作目录。这在将服务接入 VS Code / Cursor / OpenCode 等主流 AI 工具时存在不便——用户需要在 MCP 配置文件中硬编码项目路径，切换项目需要修改配置并重启服务。

**核心诉求**：
- AI 侧能否主动传入工作路径？
- MCP 服务侧能否主动获取工作路径？

#### 8.2 方案分析与对比

我们评估了以下五种获取项目工作目录的方式，最终采用"多级回退"组合策略：

| 方式 | 原理 | 优点 | 缺点 | 是否采用 |
|------|------|------|------|---------|
| **`--repo` 启动参数** | 服务启动时通过命令行传入 | 简单直接；用户意图明确 | 需要硬编码路径；切换项目必须重启 | ✅ 保留（作为最后兜底） |
| **MCP `initialize` roots** | MCP 客户端在握手时自动发送工作区 URI | 零配置；客户端自动提供；符合 MCP 协议规范 | 依赖客户端支持 roots 能力；不是所有客户端都支持 | ✅ 新增 |
| **`workspace.set_root` 工具** | AI 通过工具调用动态设置工作区 | 灵活；AI 主动控制；支持会话内切换项目 | 需要 AI 额外调用一次工具 | ✅ 新增 |
| **`workspacePath` 工具参数** | 每次工具调用可附加临时工作区覆盖 | 最灵活；可跨项目操作；不影响全局状态 | 冗余：每次调用都要传；不适合常规使用 | ✅ 新增 |
| **环境变量** | 通过 `CANGJIECODER_WORKSPACE` 等环境变量 | 与 CI/CD 集成方便；启动前设定 | 不够灵活；不能会话内动态切换 | ❌ 未采用（收益不明显） |

**选择理由**：

1. **`initialize` roots 是最推荐的方式**。它是 MCP 协议的标准能力，VS Code / Cursor 等主流客户端在连接 MCP 服务器时自动发送 roots 信息，服务端无需任何额外配置即可正确获取工作区路径。用户只需要配置一次 MCP 服务器（不含 `--repo`），就能在任何项目中自动工作。

2. **`workspace.set_root` 是最重要的补充**。当客户端不支持 roots（例如 OpenCode 的某些版本），或者需要在会话中动态切换项目时，AI 可以主动调用此工具。这是"AI 侧主动传入工作路径"的直接实现。

3. **`workspacePath` 参数提供了最大灵活性**。它不改变全局状态，适合临时跨项目查看文件的场景。但在日常使用中很少需要。

4. **未采用环境变量方式**。因为 `initialize` roots 和 `workspace.set_root` 已经覆盖了所有动态场景，环境变量仅在启动前有效，和 `--repo` 的能力重叠，额外收益不大。

**优先级设计**（从高到低）：

```
workspacePath 参数（单次覆盖）> workspace.set_root（会话级）> initialize roots（自动检测）> --repo（启动参数）> cwd（兜底）
```

这个优先级确保：显式的临时覆盖 > 显式的会话级设置 > 自动检测 > 启动时默认值。当 `--repo` 被显式指定时，`initialize` roots 不会覆盖它（尊重用户的显式意图）。

#### 8.3 实现要点

**核心变更**（`service/src/mcp_handlers.cj`）：

- `McpRuntime.workspaceRoot` 从 `let`（不可变）改为 `var`（可变），支持会话中动态修改
- `McpRuntime.hasExplicitRepo` 新增字段，记录用户是否通过 `--repo` 显式指定了工作区
- `handleInitialize()` 增加 roots 解析逻辑：从 `params.roots[0].uri` 提取 `file://` URI 并转换为本地路径
- `handleToolsCall()` 增加三层调度：
  1. 拦截 `workspace.set_root` → 直接修改 `runtime.workspaceRoot`
  2. 拦截 `workspace.get_root` → 返回当前 `workspaceRoot`
  3. 通用路径：调用 `resolveEffectiveWorkspaceRoot()` 检查 `workspacePath` 参数覆盖

**新增工具**：
- `workspace.set_root`：验证路径（绝对路径 + 目录存在 + canonicalize）后更新 `runtime.workspaceRoot`
- `workspace.get_root`：返回当前 `workspaceRoot`

**新增辅助函数**：
- `extractFirstRootPath(params)`：从 initialize 参数解析 roots
- `fileUriToPath(uri)`：将 `file:///path` URI 转换为 `/path`
- `resolveEffectiveWorkspaceRoot(default, args)`：检查 `workspacePath` 参数
- `isDirectory(path)`：通过 `Directory.isEmpty()` 检查路径是否为目录

**安全保障**：
- `workspace.set_root` 和 `workspacePath` 都要求绝对路径且目录必须存在
- 所有文件操作仍通过 `ensureWorkspacePath()` 进行防逃逸检查
- 无效的 `workspacePath` 静默回退到默认工作区（不中断工具调用）

#### 8.4 客户端配置简化

**优化前**（需要硬编码 `--repo`）：
```json
{
  "args": ["mcp-stdio", "--repo", "/absolute/path/to/workspace"]
}
```

**优化后**（无需指定 `--repo`，客户端自动提供工作区）：
```json
{
  "args": ["mcp-stdio"]
}
```

#### 8.5 新增测试

**Cangjie 单元测试**（`workspace_root_test.cj`，18 个测试用例）：
- `getRootReturnsCurrentWorkspace` — 验证 `get_root` 返回当前工作区
- `setRootUpdatesWorkspace` — 验证 `set_root` 更新 `runtime.workspaceRoot`
- `setRootRejectsEmptyPath` — 验证空路径被拒绝
- `setRootRejectsRelativePath` — 验证相对路径被拒绝
- `setRootRejectsNonexistentPath` — 验证不存在的路径被拒绝
- `setRootPersistsAcrossToolCalls` — 验证设置后对后续调用持久生效
- `initializeWithRootsUpdatesWorkspace` — 验证 initialize roots 自动设置工作区
- `initializeWithExplicitRepoIgnoresRoots` — 验证 `--repo` 指定时 roots 不覆盖
- `initializeWithoutRootsKeepsDefault` — 验证无 roots 时保持默认值
- `initializeWithInvalidRootPathKeepsDefault` — 验证无效 root 路径时保持默认值
- `workspacePathOverridesDefaultRoot` — 验证 `workspacePath` 参数临时覆盖
- `workspacePathIgnoresInvalidPath` / `workspacePathIgnoresRelativePath` — 验证无效路径处理
- `fileUriToPathParsesStandardUri` / `fileUriToPathRejectsNonFileUri` / `fileUriToPathRejectsEmptyString` — URI 解析
- `toolDefinitionsIncludeSetAndGetRoot` / `toolRegistryIncludesSetAndGetRoot` — 工具注册验证

**测试汇总**：235 个 Cangjie 测试全部通过

#### 8.6 代码架构重构

根据代码检视意见，对工作区管理代码进行了架构重构：

**新增 `cangjiecoder.workspace` 包**（`service/src/workspace/`）：

| 文件 | 职责 |
|------|------|
| `helpers.cj` | 工作区路径辅助函数：`isDirectory`、`fileUriToPath`、`extractFirstRootPath`、`resolveEffectiveWorkspaceRoot` |
| `root_manager.cj` | 工作区根目录管理业务逻辑：`workspaceSetRootJson`、`workspaceGetRootJson`、`handleWorkspaceRootPlaceholder` |
| `files.cj` | 工作区文件操作工具处理函数：read/list/search/replace/create/rollback |
| `commands.cj` | 工作区命令执行工具处理函数：run_build/run_test/run_command |

**`mcp_handlers.cj` → `mcp/handlers.cj`**：
- 移入 `cangjiecoder.mcp` 包，与 `protocol.cj` 同包
- 职责明确：纯粹的 MCP 协议请求调度（JSON-RPC 方法处理、工具调度、stdio 服务循环）
- 不再混入工作区管理的具体业务逻辑

**共享类型上提**：
- `McpToolContext` 和 `McpToolHandler` 从 `cangjiecoder.tools` 移至 `cangjiecoder.common`
- 解决了 `cangjiecoder.tools` ↔ `cangjiecoder.workspace` 的循环依赖问题

**删除旧文件**：
- `service/src/mcp_handlers.cj`（已拆分到 `mcp/handlers.cj` + `workspace/`）
- `service/src/tools/workspace.cj`（已拆分到 `workspace/files.cj` + `workspace/commands.cj`）

**依赖关系**（无循环）：
```
cangjiecoder.common  ← 共享类型（McpToolContext, McpToolHandler, AppConfig）
    ↑        ↑
cangjiecoder.workspace    cangjiecoder.tools
    ↑                         ↑
    └─────── cangjiecoder.mcp ┘
```

#### 8.7 删除 tools 目录，工具处理函数回归领域包

按检视意见彻底删除 `service/src/tools/` 目录，各工具处理函数移入其所属的领域包，MCP 工具注册表移入 `mcp/` 目录。

**变更明细**：

| 原文件 | 目标文件 | 说明 |
|--------|----------|------|
| `tools/skills.cj` | `skills/handlers.cj` | 技能搜索工具处理函数（search/batch_search/prompt_context） |
| `tools/ast.cj` | `analysis/handlers.cj` | AST 解析/查询/编辑和代码分析工具处理函数 |
| `tools/lsp.cj` + `tools/types.cj` | `lsp/handlers.cj` | LSP 查询工具处理函数（status/probe/symbols/definition）和 lspQueryToolResult |
| `tools/registry.cj` | `mcp/registry.cj` | MCP 工具注册表（buildMcpToolRegistry），与 protocol.cj 和 handlers.cj 同包 |
| `json/serializers.cj` | 各领域包 | 领域 JSON 序列化函数移入各自的包（消除 json↔领域包循环依赖） |

**领域 JSON 序列化迁移**：
- `skillsJson()` → `skills/handlers.cj` 中的 `skillsResultToJson()`
- `analysisJson()` → `analysis/handlers.cj` 中的 `analysisResultToJson()`
- `lspStatusJson()` / `lspProbeJson()` / `lspQueryJson()` → `lsp/handlers.cj` 中的 `lspStatusToJson()` / `lspProbeToJson()` / `lspQueryToJson()`

**新增辅助函数**：
- `analysis/analyzer.cj` 新增 `analysisWorkspaceRelativePath()`（子包内部工作区相对路径计算）

**删除文件**：
- `service/src/tools/`（整个目录）
- `service/src/json/serializers.cj`（内容已分散到各领域包）

**最终目录结构**（每个目录职责明确）：
```
service/src/
├── analysis/    → 代码分析 + AST/分析工具处理函数
├── common/      → 共享类型与工具函数
├── json/        → JSON 解析与通用序列化工具
├── lsp/         → LSP 协议/会话/查询 + LSP 工具处理函数
├── mcp/         → MCP 协议 + 运行时 + 工具注册表
├── skills/      → 技能注册表 + 技能搜索工具处理函数
└── workspace/   → 工作区管理 + 文件/命令工具处理函数
```

**依赖关系**（无循环）：
```
cangjiecoder.common  ← 共享类型（McpToolContext, McpToolHandler, AppConfig）
    ↑    ↑    ↑    ↑
skills analysis lsp workspace   ← 各领域包（含工具处理函数）
    ↑      ↑     ↑     ↑
    └──── cangjiecoder.mcp ────┘  ← MCP 协议 + 注册表（汇聚所有处理函数）
```

**测试汇总**：235 个测试全部通过
