# CangjieCoder Service MCP 接入说明

本文给出 `service` 作为 **stdio MCP Server** 接入主流 AI 开发工具的最小配置示例。

## 前置条件

```bash
export CANGJIE_SDK_HOME=/path/to/cangjie-sdk
source "${CANGJIE_SDK_HOME}/envsetup.sh"
export STDX_PATH=/path/to/cangjie-stdx/linux_x86_64_cjnative/dynamic/stdx
```

建议先构建一遍 `service`：

```bash
cd service
cjpm build
```

以下示例统一假设仓库位于 `/absolute/path/to/CangjieCoder`，要操作的目标仓库位于 `/absolute/path/to/workspace`。

## 推荐命令

优先使用已构建二进制：

```bash
/absolute/path/to/CangjieCoder/service/target/release/bin/main mcp-stdio --repo /absolute/path/to/workspace
```

如果你更希望每次由 `cjpm` 负责启动，也可以改成：

```bash
cjpm run --run-args "mcp-stdio --repo /absolute/path/to/workspace"
```

## VS Code

根据 VS Code MCP 文档，工作区可放在 `.vscode/mcp.json`：

```json
{
  "servers": {
    "cangjiecoder-service": {
      "type": "stdio",
      "command": "/absolute/path/to/CangjieCoder/service/target/release/bin/main",
      "args": [
        "mcp-stdio",
        "--repo",
        "/absolute/path/to/workspace"
      ],
      "env": {
        "CANGJIE_SDK_HOME": "/path/to/cangjie-sdk",
        "STDX_PATH": "/path/to/cangjie-stdx/linux_x86_64_cjnative/dynamic/stdx"
      }
    }
  }
}
```

## Cursor

Cursor 常用 `~/.cursor/mcp.json` 或项目内 `.cursor/mcp.json`：

```json
{
  "mcpServers": {
    "cangjiecoder-service": {
      "command": "/absolute/path/to/CangjieCoder/service/target/release/bin/main",
      "args": [
        "mcp-stdio",
        "--repo",
        "/absolute/path/to/workspace"
      ],
      "env": {
        "CANGJIE_SDK_HOME": "/path/to/cangjie-sdk",
        "STDX_PATH": "/path/to/cangjie-stdx/linux_x86_64_cjnative/dynamic/stdx"
      }
    }
  }
}
```

## OpenCode

OpenCode 的本地 MCP 示例可写成：

```json
{
  "mcp": {
    "cangjiecoder-service": {
      "type": "local",
      "command": [
        "/absolute/path/to/CangjieCoder/service/target/release/bin/main",
        "mcp-stdio",
        "--repo",
        "/absolute/path/to/workspace"
      ],
      "enabled": true,
      "env": {
        "CANGJIE_SDK_HOME": "/path/to/cangjie-sdk",
        "STDX_PATH": "/path/to/cangjie-stdx/linux_x86_64_cjnative/dynamic/stdx"
      }
    }
  }
}
```

## 调试建议

- 先在终端手工运行 `service` 的 `mcp-stdio`，确认可以正常启动
- 优先使用绝对路径
- 模型密钥只需要配置给 `agent`，不要配置到 `service` 或写入仓库
- 如果需要更强的仓颉分析能力，可同时配置：

```bash
export TREE_SITTER_CANGJIE=tree-sitter
export CJLINT_COMMAND=cjlint
export CANGJIE_LSP_COMMAND=/path/to/LSPServer
```

> VS Code / Cursor / OpenCode 的 MCP 配置格式会演进，以上示例基于当前公开文档整理，若客户端版本变更，请以各自最新文档为准。
