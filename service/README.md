# CangjieCoder Service

`service/` 是 Cangjie AI Coder 的底层服务，负责：

- 暴露 HTTP API 与 stdio MCP Server
- 提供 Cangjie 专用 Skills、LSP 探测/跳转/符号查询、内置 tree-sitter AST 解析/查询、AST 编辑、工程模板、文件/命令/构建/测试工具
- 作为 VS Code / Cursor / OpenCode / 自定义 Agent 的可复用后端能力层

## 目录说明

```text
service/
├── cjpm.toml       # 项目配置（依赖 cangjie-tree-sitter 库）
├── src/
│   ├── ast/        # AST 服务层（基于 cangjie-tree-sitter 库的薄代理）
│   ├── analysis/   # 代码分析与 AST 编辑（依赖外部 tree-sitter CLI）
│   ├── common/     # 共享类型与工具函数
│   ├── json/       # JSON 解析与序列化工具
│   ├── lsp/        # LSP 协议、会话管理与查询
│   ├── mcp/        # MCP 协议层（工具定义、帧编解码）
│   ├── projects/   # 项目模板管理
│   └── skills/     # 技能注册表
└── README.md
```

> `service` 运行时会优先从自身目录寻找 `examples/` 和 `.github/skills/`；如果没有找到，则自动回退到仓库根目录中的同名资源目录，因此当前 monorepo 结构可以直接工作。

## 依赖

`service` 依赖同仓库中的 `cangjie-tree-sitter` 动态库（通过 `[dependencies]` 引用），用于内置 AST 解析。需要先编译 C 共享库：

```bash
export CANGJIE_SDK_HOME=/path/to/cangjie-sdk
source "${CANGJIE_SDK_HOME}/envsetup.sh"
export STDX_PATH=/path/to/cangjie-stdx/linux_x86_64_cjnative/dynamic/stdx

# 预编译 tree-sitter C 共享库（首次构建前需要执行）
cd ../cangjie-tree-sitter/treesitter && make && cd ../../service
```

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

## MCP 工具列表

### 技能搜索

| 工具名 | 说明 |
|--------|------|
| `skills.search` | 搜索内置的仓颉技能语料 |

### 工作区文件与命令

| 工具名 | 说明 |
|--------|------|
| `workspace.read_file` | 读取仓库内文件 |
| `workspace.list_files` | 递归列举仓库内文件 |
| `workspace.search_text` | 在仓库文件中搜索文本 |
| `workspace.replace_text` | 精确替换文件中的一处文本 |
| `workspace.create_file` | 创建文件并自动建立父目录 |
| `workspace.run_build` | 在工作区中运行 `cjpm build` |
| `workspace.run_test` | 在工作区中运行 `cjpm test` |
| `workspace.run_command` | 运行受限白名单命令 |
| `workspace.rollback` | 回滚所有文件修改到编辑前状态 |

### Cangjie 分析与 AST

| 工具名 | 说明 |
|--------|------|
| `cangjie.analyze_file` | 运行 tree-sitter/cjlint/cjc 逐级分析 |
| `cangjie.edit_ast_node` | 通过 tree-sitter 定位 AST 节点并替换 |
| `cangjie.ast_parse` | 内置 tree-sitter 解析，返回 S-expression AST |
| `cangjie.ast_query_nodes` | 按节点类型查询 AST 节点及位置 |
| `cangjie.ast_list_nodes` | 列出命名 AST 节点概览 |

### Cangjie LSP 集成

| 工具名 | 说明 |
|--------|------|
| `cangjie.lsp_status` | 检测 LSP 二进制是否可用 |
| `cangjie.lsp_probe` | 轻量 LSP 初始化探测 |
| `cangjie.lsp_document_symbols` | 查询文档符号 |
| `cangjie.lsp_workspace_symbols` | 查询工作区级符号 |
| `cangjie.lsp_definition` | 解析符号定义位置 |

### 项目模板

| 工具名 | 说明 |
|--------|------|
| `project.list_examples` | 列出可引导的示例项目 |
| `project.bootstrap_json_parser` | 将 JsonParser 示例复制到工作区 |

> `service` 不再直接承载 AI Provider / 会话记忆能力；这些逻辑已经全部迁移到 `agent/`，因此 `service` 可以作为更纯粹的仓颉工具服务独立复用。

当前这批能力已经覆盖“读文件/搜文本/创建文件/精确替换/构建测试/符号发现/定义跳转/AST 定点编辑/内置 AST 解析”的自主开发闭环，适合通过 stdio MCP 接入到 OpenCode、Copilot 等宿主中使用。

更多工具详情和客户端接入示例见根目录 [`mcp.md`](../mcp.md)。
