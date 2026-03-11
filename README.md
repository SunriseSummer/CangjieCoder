# CangjieCoder

CangjieCoder 由三个仓颉项目组成：

- `cangjie-tree-sitter/`：tree-sitter 引擎的仓颉封装（动态库），内置 Cangjie 语法插件，支持接入更多语言
- `service/`：底层 Cangjie AI Coding Service，专注提供 stdio MCP 服务与 Cangjie 专用工具能力
- `agent/`：面向仓颉项目开发的单智能体应用，通过 stdio MCP 调用 `service`

补充文档：

- [`service/README.md`](service/README.md)：`service` 的能力、构建和运行说明
- [`agent/README.md`](agent/README.md)：`agent` 的使用方式
- [`mcp.md`](mcp.md)：MCP 工具完整参考与客户端接入示例
- [`docs/serve-mode-and-roadmap.md`](docs/serve-mode-and-roadmap.md)：历史能力说明与演进背景（HTTP 服务已移除）

## 目录结构

```text
.
├── cangjie-tree-sitter/  # tree-sitter 仓颉封装库（动态库，可独立复用）
├── service/              # MCP 工具服务（底层能力，仅 stdio MCP）
├── agent/                # 单智能体应用（大脑）
├── tests/                # Python 集成测试与端到端测试
│   ├── e2etest_jsonparser/      # 端到端: JSON 解析器项目（编译迭代）
│   ├── e2etest_taskmanager/     # 端到端: 任务管理器（AST 编辑/LSP 工具）
│   ├── e2etest_skills_ast_lsp/  # 端到端: Skills 能力 + AST/LSP 最优实践
│   └── cangjie/                 # 测试工作区
├── docs/                 # 补充说明文档
├── .github/skills/       # 仓颉 Skills 语料
└── cangjie-docs-full/    # 仓颉语言完整文档
```

## 环境准备

构建和测试依赖如下：

- Cangjie SDK 1.0.5
- 模型 API Key（仅在运行 `agent/` 时通过环境变量注入，不写入仓库）

示例：

```bash
# 1) 解压 SDK 与 stdx
export CANGJIE_SDK_HOME=/path/to/cangjie-sdk
source "${CANGJIE_SDK_HOME}/envsetup.sh"
export STDX_PATH=/path/to/cangjie-stdx/linux_x86_64_cjnative/dynamic/stdx

# 2) 配置模型 Key（仅 agent 需要；示例变量名，不要把密钥写入代码）
export KIMI_API_KEY=your_kimi_api_key
```

## 构建与测试

仓库根目录是一个 `cjpm` workspace（含 `cangjie-tree-sitter`、`service`、`agent` 三个成员），可以直接统一验证：

```bash
# 1) 预编译 tree-sitter C 共享库
cd cangjie-tree-sitter/treesitter && make && cd ../..

# 2) 构建与测试全部项目
cjpm build
cjpm test
```

也可以分别进入子项目：

```bash
cd cangjie-tree-sitter && cjpm build && cjpm test
cd ../service && cjpm build && cjpm test
cd ../agent && cjpm build && cjpm test
```

## 快速开始

### 1. 启动 service 的 stdio MCP

```bash
cd service
cjpm run --run-args "mcp-stdio --repo /absolute/path/to/workspace"
```

### 2. 运行单智能体

```bash
cd agent
cjpm run --run-args "--workspace /absolute/path/to/workspace --prompt 为当前仓颉项目生成重构计划并执行必要的构建测试"
```

默认模型为 **Kimi 2.5**（`kimi-k2.5`）。所有 AI Provider、会话记忆与最终总结逻辑由 `agent/` 本地负责，`service/` 专注提供 MCP 工具能力（含 tree-sitter AST 解析、LSP 符号查询、定义跳转、文件创建与 AST 编辑等能力）。
