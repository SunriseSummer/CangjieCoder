# CangjieCoder

一个用仓颉编程语言实现的轻量 AI 软件开发工具骨架，专门优化仓颉项目开发场景。

## 当前实现能力

- 优雅可扩展的模块化架构：`skills` / `providers` / `conversation` / `projects` / `mcp_protocol` / `ast_edit` / `server`
- 内置 Skills 注册表，直接复用仓库里的 `.github/skills/*/SKILL.md`
- 内置主流模型接入配置：
  - `kimi`（Moonshot / Kimi）
  - `glm`（Zhipu GLM）
- 提供 Cangjie 专用上下文增强：
  - 根据用户问题自动检索本地 Skills
  - 将 Skills 摘要拼接到系统提示词，弥补模型仓颉知识不足
  - 可选接入 `tree-sitter` / `cjlint` / `cjc` 做精确分析，减少无效 Token
- 内置第一个“自主开发”示例工程：
  - `JsonParser` 示例项目模板，可直接复制到工作区继续开发
- 提供可选的 Cangjie LSP 集成入口：
  - 自动探测 `LSPServer`
  - 支持通过环境变量显式配置 LSP 命令
  - 暴露 CLI / HTTP / MCP 的 LSP 状态检查与 initialize probe 能力
- 提供多轮会话记忆：
  - 服务端按 `sessionId` 保存最近对话
  - `/chat` 与 MCP `conversation.chat` 自动带入历史轮次
- 提供 HTTP API + MCP 风格 JSON-RPC 工具入口：
  - `/skills`
  - `/skills/search`
  - `/providers`
  - `/projects/examples`
  - `/bootstrap/json-parser`
  - `/analyze`
  - `/lsp/status`
  - `/lsp/probe`
  - `/conversations/start`
  - `/conversations/history`
  - `/ast/edit`
  - `/chat`
  - `/mcp`
- MCP 工具：
  - `skills.search`
  - `workspace.read_file`
  - `workspace.replace_text`
  - `cangjie.analyze_file`
  - `project.list_examples`
  - `project.bootstrap_json_parser`
  - `conversation.start_session`
  - `conversation.get_history`
  - `conversation.chat`
  - `cangjie.lsp_status`
  - `cangjie.lsp_probe`
  - `cangjie.edit_ast_node`

## 目录结构

```text
src/
├── core.cj       # 配置、文件操作、安全编辑、进程执行
├── conversation.cj # 多轮会话内存
├── mcp_protocol.cj # MCP tools/list schema 元数据
├── ast_edit.cj   # tree-sitter AST 节点级替换（首版）
├── projects.cj   # 示例项目模板与 LSP 状态探测
├── skills.cj     # Skills 加载与检索
├── providers.cj  # GLM / KIMI 模型接入
├── server.cj     # HTTP API 与 MCP JSON-RPC 入口
├── main.cj       # CLI 入口
├── conversation_test.cj
├── mcp_protocol_test.cj
├── ast_edit_test.cj
├── skills_test.cj
└── projects_test.cj
```

## 为什么这样设计

仓颉是新语言，通用大模型预置知识较弱。当前实现采用三层增强策略：

1. **Skills 优先**：先从本地仓颉 Skills 中检索相关知识
2. **精确分析优先**：优先调用 `tree-sitter`，失败后回退 `cjlint` / `cjc`
3. **模型调用后置**：把精简后的仓颉上下文交给 KIMI / GLM，降低提示词噪音和 Token 消耗
4. **模板先行**：把典型仓颉项目（当前先内置 `JsonParser`）沉淀成可复制模板，让工具第一版就能启动一个真实仓颉项目
5. **会话与协议并进**：用多轮会话记忆 + 带 schema 的 MCP tools/list，让 AI 代理在更少猜测下完成工具调用

这套链路适合继续扩展成更强的代码代理、补全器、重构器和多工具编排框架。

## 依赖配置

### 1. 安装仓颉 SDK 和 stdx

- SDK：<https://github.com/SunriseSummer/CangjieSDK/releases/tag/1.0.5>
- `stdx` 路径通过环境变量 `STDX_PATH` 注入到 `cjpm.toml`

示例：

```bash
export STDX_PATH=/path/to/stdx/dynamic/stdx
```

### 2. 配置模型 Key

```bash
export KIMI_API_KEY=your_kimi_key
export GLM_API_KEY=your_glm_key
```

### 3. 可选：接入精确分析工具

```bash
export TREE_SITTER_CANGJIE=tree-sitter
export CJLINT_COMMAND=cjlint
export CJC_COMMAND=cjc
export CANGJIE_LSP_COMMAND=/path/to/LSPServer
```

> `TREE_SITTER_CANGJIE` 需要对应命令已具备仓颉 grammar 支持。

如果你已经安装了 1.0.5 SDK，也可以直接设置：

```bash
export CANGJIE_SDK_HOME=/path/to/cangjie
```

这样 CangjieCoder 会自动尝试从 `${CANGJIE_SDK_HOME}/tools/bin/LSPServer` 发现 LSP。

## 使用方式

### CLI

```bash
cjpm run --run-args "providers"
cjpm run --run-args "skills-search http"
cjpm run --run-args "examples"
cjpm run --run-args "bootstrap-json-parser target/my-json-parser"
cjpm run --run-args "analyze src/main.cj"
cjpm run --run-args "lsp-status"
cjpm run --run-args "lsp-probe"
cjpm run --run-args "serve --repo /absolute/path/to/repo --host 127.0.0.1 --port 8080"
```

### HTTP API

#### 搜索 Skills

```bash
curl -X POST http://127.0.0.1:8080/skills/search \
  -H 'content-type: application/json' \
  -d '{"query":"http server json"}'
```

#### 聊天调用（自动注入仓颉 Skills 上下文）

```bash
curl -X POST http://127.0.0.1:8080/chat \
  -H 'content-type: application/json' \
  -d '{
    "provider":"kimi",
    "model":"kimi-k2-0711-preview",
    "prompt":"帮我实现一个仓颉 HTTP 服务端入口",
    "analyzePath":"src/main.cj"
  }'
```

#### 多轮会话聊天

```bash
curl -X POST http://127.0.0.1:8080/chat \
  -H 'content-type: application/json' \
  -d '{
    "sessionId":"demo-session",
    "provider":"kimi",
    "prompt":"先分析这个仓颉项目结构"
  }'

curl -X POST http://127.0.0.1:8080/chat \
  -H 'content-type: application/json' \
  -d '{
    "sessionId":"demo-session",
    "provider":"kimi",
    "prompt":"基于上一轮，继续给出下一步修改建议"
  }'
```

#### 启动一个仓颉 JsonParser 示例项目

```bash
curl -X POST http://127.0.0.1:8080/bootstrap/json-parser \
  -H 'content-type: application/json' \
  -d '{"path":"target/generated-json-parser"}'
```

#### 查看当前内置项目模板

```bash
curl http://127.0.0.1:8080/projects/examples
```

#### 查看 LSP 接入状态

```bash
curl http://127.0.0.1:8080/lsp/status
```

#### 执行一次 LSP initialize probe

```bash
curl http://127.0.0.1:8080/lsp/probe
```

#### 创建与查看会话

```bash
curl -X POST http://127.0.0.1:8080/conversations/start -d '{}'

curl -X POST http://127.0.0.1:8080/conversations/history \
  -H 'content-type: application/json' \
  -d '{"sessionId":"demo-session"}'
```

#### AST 节点级替换（首版）

```bash
curl -X POST http://127.0.0.1:8080/ast/edit \
  -H 'content-type: application/json' \
  -d '{
    "path":"src/main.cj",
    "nodeType":"function_definition",
    "index":"0",
    "replacement":"func demo(): Unit { println(\"hello\") }"
  }'
```

#### MCP JSON-RPC

```bash
curl -X POST http://127.0.0.1:8080/mcp \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

调用工具：

```bash
curl -X POST http://127.0.0.1:8080/mcp \
  -H 'content-type: application/json' \
  -d '{
    "jsonrpc":"2.0",
    "id":2,
    "method":"tools/call",
    "params":{
      "name":"skills.search",
      "arguments":{"query":"json http"}
    }
  }'
```

也可以通过 MCP 直接生成第一个仓颉项目模板：

```bash
curl -X POST http://127.0.0.1:8080/mcp \
  -H 'content-type: application/json' \
  -d '{
    "jsonrpc":"2.0",
    "id":3,
    "method":"tools/call",
    "params":{
      "name":"project.bootstrap_json_parser",
      "arguments":{"path":"target/generated-json-parser"}
    }
  }'
```

MCP `tools/list` 现在会返回每个工具的 `inputSchema`，便于客户端自动发现参数结构。

还可以通过 MCP 使用多轮会话与 AST 编辑能力：

```bash
curl -X POST http://127.0.0.1:8080/mcp \
  -H 'content-type: application/json' \
  -d '{
    "jsonrpc":"2.0",
    "id":4,
    "method":"tools/call",
    "params":{
      "name":"conversation.start_session",
      "arguments":{}
    }
  }'

curl -X POST http://127.0.0.1:8080/mcp \
  -H 'content-type: application/json' \
  -d '{
    "jsonrpc":"2.0",
    "id":5,
    "method":"tools/call",
    "params":{
      "name":"cangjie.edit_ast_node",
      "arguments":{
        "path":"src/main.cj",
        "nodeType":"function_definition",
        "index":0,
        "replacement":"func demo(): Unit { println(\"hello\") }"
      }
    }
  }'
```

## 第一个可自主启动的仓颉项目：JsonParser

仓库现在自带 `examples/json_parser/`，这是一个可直接 `cjpm build` / `cjpm test` 的手写 JSON 解析器示例工程，作为 CangjieCoder 第一版“自主开发仓颉项目”的落地样板：

- 解析对象、数组、字符串、数字、布尔和 `null`
- 自带 `main.cj`
- 自带单元测试
- 可以通过 CLI / HTTP / MCP 一键复制到工作区目标目录

验证示例：

```bash
cd examples/json_parser
cjpm build
cjpm test
```

## 当前边界

当前提交实现的是一个 **可运行的基础骨架 + 第一个可复制项目模板 + 首版会话/LSP/AST 能力**：

- 已打通 Skills / MCP / GLM / KIMI / Cangjie 分析适配层
- 已提供安全的文件读取与精确文本替换能力
- 已提供第一个可直接继续开发的 `JsonParser` 示例项目
- 已支持多轮会话内存与会话历史查询
- 已把 MCP `tools/list` 扩展为带 `inputSchema` 的机器可发现协议输出
- 已接入 LSP 二进制发现、状态检查与 initialize probe
- 已提供首版 tree-sitter AST 节点级替换入口（依赖可用的 `TREE_SITTER_CANGJIE`）
- 后续可以继续扩展：
  - 持久化会话记忆（当前为进程内存）
  - 更完整的 MCP prompts/resources/streaming 能力
  - LSP 持久会话与 hover / definition / diagnostic 请求
  - tree-sitter AST 查询与更细粒度节点编辑
  - 多模型路由与工具规划
