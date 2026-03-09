# CangjieCoder Service

`service/` 是 Cangjie AI Coder 的底层服务，负责：

- 暴露 HTTP API 与 stdio MCP Server
- 提供 Cangjie 专用 Skills、LSP 探测、AST 编辑、工程模板、文件/命令/构建/测试工具
- 作为 VS Code / Cursor / OpenCode / 自定义 Agent 的可复用后端能力层

## 目录说明

```text
service/
├── cjpm.toml
├── src/
└── README.md
```

> `service` 运行时会优先从自身目录寻找 `examples/` 和 `.github/skills/`；如果没有找到，则自动回退到仓库根目录中的同名资源目录，因此当前 monorepo 结构可以直接工作。

## 依赖

```bash
export CANGJIE_SDK_HOME=/path/to/cangjie-sdk
source "${CANGJIE_SDK_HOME}/envsetup.sh"
export STDX_PATH=/path/to/cangjie-stdx/linux_x86_64_cjnative/dynamic/stdx
export KIMI_API_KEY=your_kimi_api_key
export OPENROUTER_API_KEY=your_openrouter_api_key
```

默认 Kimi 模型已调整为 **`kimi-k2.5`**。

目前内置 provider：

- `kimi`
- `glm`
- `openrouter`（可配合 `openrouter/free` 或具体 `:free` 模型实验）

## 构建与测试

```bash
cd service
cjpm build
cjpm test
```

## 启动方式

### HTTP 服务

```bash
cd service
cjpm run --run-args "serve --repo /absolute/path/to/workspace --host 127.0.0.1 --port 8080"
```

### stdio MCP 服务

```bash
cd service
cjpm run --run-args "mcp-stdio --repo /absolute/path/to/workspace"
```

`--repo` 指向要被分析/修改/构建/测试的目标仓库；如果省略，则默认作用于 `service` 当前目录。

## 主要 MCP 工具

- `skills.search`
- `workspace.read_file`
- `workspace.list_files`
- `workspace.search_text`
- `workspace.replace_text`
- `workspace.run_build`
- `workspace.run_test`
- `workspace.run_command`
- `cangjie.analyze_file`
- `project.list_examples`
- `project.bootstrap_json_parser`
- `conversation.chat`
- `cangjie.lsp_status`
- `cangjie.lsp_probe`
- `cangjie.edit_ast_node`

更多客户端接入示例见根目录 [`mcp.md`](../mcp.md)。
