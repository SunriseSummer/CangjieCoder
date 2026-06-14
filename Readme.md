# Cangjie Coder

使用仓颉编程语言（Cangjie）实现的 AI Coding Agent 命令行工具。

基于 OpenAI Function Calling 协议，通过多轮工具调用自动完成代码读写、检索、执行等编程任务。交互形态参考 [aider](https://github.com/Aider-AI/aider)、[Claude Code](https://docs.anthropic.com/en/docs/claude-code) 等项目。

## 核心功能

- **Agent 模式**：ReAct 风格的多轮工具调用循环，AI 自主规划并执行编程任务
- **10 个内置工具**：文件读写、目录浏览、glob/grep 搜索、命令执行、任务清单、Skill 加载
- **三档审批策略**：`auto`（全部放行）/ `default`（敏感工具询问确认）/ `readonly`（禁止写操作）
- **文件变更追踪**：`/diff` 查看变更、`/undo` 逐步回滚，基于栈式快照
- **历史压缩**：`/compact` 本地确定性算法压缩对话历史，保持协议完整性
- **Skills 系统**：自动发现项目 `.agents/skills/` 目录，懒加载领域知识
- **多服务商支持**：华为云 MaaS、Moonshot、DeepSeek、智谱 GLM、自定义 OpenAI 兼容接口
- **思考模型兼容**：支持 `reasoning_content` 字段回传（kimi-k2.6、DeepSeek R1 等）
- **流式聊天**：`chat` 模式保留 SSE 流式输出，适合纯问答

## 支持的服务商与模型

| 服务商 | ID | Endpoint | 模型 |
| --- | --- | --- | --- |
| 华为云 MaaS | `huawei` | `https://api.modelarts-maas.com/v2/chat/completions` | kimi-k2.6, glm-5.1, deepseek-v4-pro |
| Moonshot | `kimi` | `https://api.moonshot.cn/v1/chat/completions` | kimi-k2.6, kimi-k2.5, moonshot-v1-128k 等 |
| DeepSeek | `deepseek` | `https://api.deepseek.com/chat/completions` | deepseek-v4-pro, deepseek-v4-flash, deepseek-reasoner |
| 智谱 GLM | `zhipu` | `https://open.bigmodel.cn/api/paas/v4/chat/completions` | glm-5.1, glm-4.6, glm-4-plus 等 |
| 自定义 | `custom` | 用户自行输入 BaseURL | 用户自行指定 |

> **Custom 服务商说明**：选择 `custom` 后，需手动输入 OpenAI 兼容的 `chat/completions` 接口 BaseURL（如 `https://your-server.com/v1/chat/completions`）和 API Key。适用于自建模型服务、第三方代理或任何遵循 OpenAI Function Calling 协议的接口。

## 构建与运行

### 环境要求

- Cangjie SDK 1.0.5
- Cangjie stdx 1.0.5.1

### 安装 SDK

```bash
# 安装 Cangjie SDK
curl -L -o sdk.tar.gz \
  https://github.com/SunriseSummer/CangjieSDK/releases/download/1.0.5/cangjie-sdk-linux-x64-1.0.5.tar.gz
tar -xzf sdk.tar.gz -C /opt/
source /opt/cangjie/envsetup.sh

# 安装 stdx（路径须与 cjpm.toml 中的 path-option 一致）
curl -L -o stdx.zip \
  https://github.com/SunriseSummer/CangjieSDK/releases/download/1.0.5/cangjie-stdx-linux-x64-1.0.5.1.zip
unzip stdx.zip -d /opt/cangjie
```

### 构建

```bash
cd coder
cjpm build
```

### 运行

```bash
cjpm run
# 或直接执行编译产物
export LD_LIBRARY_PATH=/opt/cangjie/linux_x86_64_cjnative/dynamic/stdx:$LD_LIBRARY_PATH
target/release/bin/main
```

### 命令行选项

| 选项 | 说明 |
| --- | --- |
| `--insecure-tls` | 禁用 TLS 证书校验（TrustAll，仅用于调试/内网） |
| `--ca-bundle=PATH` | 自定义 CA PEM bundle 文件路径 |
| `--tls-debug` | 打印 CA 加载数量等 TLS 调试信息 |

```bash
# 示例：使用私有 CA 启动
target/release/bin/main --ca-bundle=/etc/pki/my-ca.pem

# 示例：跳过证书校验（仅限调试）
target/release/bin/main --insecure-tls
```

## 使用说明

首次启动自动进入 `/connect` 引导，选择服务商并输入 API Key。默认进入 agent 模式，输入自然语言任务即可。

### 命令一览

| 命令 | 说明 |
| --- | --- |
| `/help` | 查看命令帮助 |
| `/connect [provider]` | 切换服务商，设置 API Key |
| `/model [id]` | 查看或切换模型 |
| `/mode [chat\|agent]` | 切换交互模式 |
| `/approve [auto\|default\|readonly]` | 设置审批策略 |
| `/tools` | 列出已注册工具 |
| `/todo` | 查看任务清单 |
| `/skills` | 重新扫描 Skills |
| `/diff` | 查看文件变更 |
| `/undo` | 撤销上一次文件变更 |
| `/compact` | 压缩对话历史 |
| `/system [text]` | 查看或修改 system prompt |
| `/status` | 显示当前状态 |
| `/clear` | 清空对话历史 |
| `/exit` | 退出 |

### 内置工具

| 工具 | 安全级别 | 用途 |
| --- | --- | --- |
| `read_file` | safe | 按行范围读取文件 |
| `list_dir` | safe | 列出目录内容，自动排除噪声目录 |
| `glob_search` | safe | 文件名 glob 匹配 |
| `grep_search` | safe | 目录树内正则搜索 |
| `edit_file` | sensitive | 精确字符串替换（old_str 必须唯一） |
| `write_file` | sensitive | 创建或覆盖文件 |
| `run_bash` | sensitive | 执行 shell 命令 |
| `todo_write` | safe | 写入任务清单 |
| `todo_read` | safe | 读取任务清单 |
| `use_skill` | safe | 按需加载 Skill 正文 |

### Skills 目录约定

```
<project>/.agents/skills/<skill-name>/SKILL.md
```

SKILL.md 须包含 YAML frontmatter：

```yaml
---
name: <skill-name>
description: "<description>"
---
<正文>
```

启动时仅读取 frontmatter 注入系统提示，AI 通过 `use_skill` 按需加载完整正文。

## 测试

```bash
cjpm test                                              # 单元测试（199 用例）
python3 e2etest/run_all.py --mock-only                 # Mock E2E（4 场景）
python3 e2etest/run_all.py --provider zhipu             # 实战 E2E（需 API Key）
python3 e2etest/run_all.py --cangjie --provider deepseek # 仓颉 AI Coding（需 SDK + API Key）
```

详见 [e2etest/README.md](e2etest/README.md)。

## 项目结构

```
coder/
├── cjpm.toml
├── src/
│   ├── main.cj                  # 入口
│   ├── app/                     # REPL 主流程与初始化
│   ├── agent/                   # Agent Loop、审批、系统提示
│   ├── tools/                   # 工具接口与 10 个内置工具
│   ├── httpx/                   # HTTP 客户端与 OpenAI 协议
│   ├── commands/                # 斜杠命令
│   ├── config/                  # 配置持久化
│   ├── provider/                # 服务商预设（5 个，含 custom）
│   ├── session/                 # 流式聊天会话
│   └── skillset/                # Skills 加载
└── e2etest/                     # 端到端测试（Python）
```
