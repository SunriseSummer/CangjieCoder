# CangjieCoder

CangjieCoder 现在拆分为两个仓颉项目：

- `service/`：底层 Cangjie AI Coding Service，提供 HTTP / stdio MCP / Cangjie 专用工具能力
- `agent/`：面向仓颉项目开发的单智能体应用，通过 stdio MCP 调用 `service`

补充文档：

- [`service/README.md`](service/README.md)：`service` 的能力、构建和运行说明
- [`agent/README.md`](agent/README.md)：`agent` 的使用方式
- [`mcp.md`](mcp.md)：在 VS Code / Cursor / OpenCode 中配置 `service` MCP 的示例
- [`docs/serve-mode-and-roadmap.md`](docs/serve-mode-and-roadmap.md)：历史能力说明与演进背景

## 目录结构

```text
.
├── agent/          # 单智能体应用（大脑）
├── service/        # MCP / HTTP / Cangjie 工具服务（底层能力）
├── examples/       # service 内置模板资源
├── docs/           # 补充说明文档
├── .github/skills/ # 仓颉 Skills 语料
└── cangjie-docs-full/
```

## 环境准备

题目要求的构建和测试依赖如下：

- Cangjie SDK 1.0.5
- cangjie-stdx-linux-x64-1.0.5.1
- Kimi API Key（运行智能体时通过环境变量注入，不写入仓库）

示例：

```bash
# 1) 解压 SDK 与 stdx
export CANGJIE_SDK_HOME=/path/to/cangjie-sdk
source "${CANGJIE_SDK_HOME}/envsetup.sh"
export STDX_PATH=/path/to/cangjie-stdx/linux_x86_64_cjnative/dynamic/stdx

# 2) 配置模型 Key（示例变量名，不要把密钥写入代码）
export KIMI_API_KEY=your_kimi_api_key
```

## 构建与测试

仓库根目录现在是一个 `cjpm` workspace，可以直接统一验证：

```bash
cd /path/to/CangjieCoder
cjpm build
cjpm test
```

也可以分别进入子项目：

```bash
cd service && cjpm build && cjpm test
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

默认模型为 **Kimi 2.5**（`kimi-k2.5`），并通过 `conversation.chat` 生成工具执行计划，再由智能体依次调用 `service` 的 MCP 工具完成任务。
