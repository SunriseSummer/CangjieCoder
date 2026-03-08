# CangjieCoder

一个用仓颉编程语言实现的轻量 AI 软件开发工具骨架，专门优化仓颉项目开发场景。

## 当前实现能力

- 优雅可扩展的模块化架构：`skills` / `providers` / `server` / `analyzer`
- 内置 Skills 注册表，直接复用仓库里的 `.github/skills/*/SKILL.md`
- 内置主流模型接入配置：
  - `kimi`（Moonshot / Kimi）
  - `glm`（Zhipu GLM）
- 提供 Cangjie 专用上下文增强：
  - 根据用户问题自动检索本地 Skills
  - 将 Skills 摘要拼接到系统提示词，弥补模型仓颉知识不足
  - 可选接入 `tree-sitter` / `cjlint` / `cjc` 做精确分析，减少无效 Token
- 提供 HTTP API + MCP 风格 JSON-RPC 工具入口：
  - `/skills`
  - `/skills/search`
  - `/providers`
  - `/analyze`
  - `/chat`
  - `/mcp`
- MCP 工具：
  - `skills.search`
  - `workspace.read_file`
  - `workspace.replace_text`
  - `cangjie.analyze_file`

## 目录结构

```text
src/
├── core.cj       # 配置、文件操作、安全编辑、进程执行
├── skills.cj     # Skills 加载与检索
├── providers.cj  # GLM / KIMI 模型接入
├── server.cj     # HTTP API 与 MCP JSON-RPC 入口
├── main.cj       # CLI 入口
└── skills_test.cj
```

## 为什么这样设计

仓颉是新语言，通用大模型预置知识较弱。当前实现采用三层增强策略：

1. **Skills 优先**：先从本地仓颉 Skills 中检索相关知识
2. **精确分析优先**：优先调用 `tree-sitter`，失败后回退 `cjlint` / `cjc`
3. **模型调用后置**：把精简后的仓颉上下文交给 KIMI / GLM，降低提示词噪音和 Token 消耗

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
```

> `TREE_SITTER_CANGJIE` 需要对应命令已具备仓颉 grammar 支持。

## 使用方式

### CLI

```bash
cjpm run --run-args "providers"
cjpm run --run-args "skills-search http"
cjpm run --run-args "analyze src/main.cj"
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

## 当前边界

当前提交实现的是一个 **可运行的基础骨架**：

- 已打通 Skills / MCP / GLM / KIMI / Cangjie 分析适配层
- 已提供安全的文件读取与精确文本替换能力
- 后续可以继续扩展：
  - 多轮会话记忆
  - 更完整的 MCP 协议能力
  - LSP 持久会话
  - tree-sitter AST 级代码编辑
  - 多模型路由与工具规划
