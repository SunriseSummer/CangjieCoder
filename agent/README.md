# CangjieCoder Agent

`agent/` 是首个可跑通的单智能体应用。它会：

1. 通过 stdio MCP 拉起并调用 `service`
2. 读取工具列表和工作区快照
3. 在 `agent` 本地使用 Provider + 会话记忆（默认 Kimi 2.5，也支持 OpenRouter）生成 JSON 计划
4. 进入有界的 **plan -> act -> review -> replan** 多轮执行循环
5. 对修改型操作自动补充 `build/test` 验证，并输出最终总结

## 当前架构

参考 LangGraph / AutoGen / SmolAgents 等社区常见设计，当前 `agent` 采用单进程、单智能体、可多轮收敛的结构：

- `main.cj`：薄入口
- `agent_core.cj`：配置、核心数据结构、公共工具
- `ai_core.cj`：AI Provider、会话记忆与模型调用封装
- `mcp_client.cj`：stdio MCP transport 与工具调用封装
- `planner.cj`：计划生成、计划解析、本地 fallback heuristic、replan prompt
- `executor.cj`：执行结果格式化、自动验证、最终总结
- `runner.cj`：运行主循环，负责 round-based observe / plan / act / review / replan

当前实现仍保持“轻量单体 agent”，但已经具备：

- 会话级 LLM memory（由 agent 本地维护）
- 多轮 replan
- 已执行步骤去重，避免重复工具调用
- 模型不可用时的本地启发式 fallback
- 修改操作后的自动构建/测试验证
- 与 `service` 工具集的低耦合编排
- 基于 `service` 新增的 LSP 文档/工作区符号工具做更细粒度分析

## 运行

```bash
cd agent
cjpm run --run-args "--workspace /absolute/path/to/workspace --prompt 在当前仓颉项目中分析问题并执行必要修改"
```

模型环境变量（按所选 Provider 注入）：

- `KIMI_API_KEY`
- `GLM_API_KEY`
- `OPENROUTER_API_KEY`

可选参数：

- `--service-dir /absolute/path/to/CangjieCoder/service`
- `--provider kimi|glm|openrouter`
- `--model kimi-k2.5`
- `--max-rounds 2`
- `--prompt ...`

默认会优先调用 `../service/target/release/bin/main`；如果该二进制尚未构建，则回退为在 `service/` 目录下执行 `cjpm run --run-args "mcp-stdio ..."`。

## 免费模型实验路径

当前 `agent` 已支持：

- `kimi`
- `glm`
- `openrouter`

其中 `openrouter` 适合作为低门槛实验入口。可以直接尝试：

```bash
export OPENROUTER_API_KEY=your_openrouter_key

cd agent
cjpm run --run-args "--workspace /absolute/path/to/workspace --provider openrouter --model openrouter/free --prompt 为当前仓颉项目生成诊断和修复计划"
```

也可以手工指定社区常见的免费模型 ID（可用性随时间变化）：

- `mistralai/devstral-2:free`
- `deepseek/deepseek-r1:free`
- `google/gemini-2.0-flash:free`

如果希望在 OpenRouter 后台看到更清晰的应用来源，可再设置：

```bash
export OPENROUTER_HTTP_REFERER=https://your-app.example
export OPENROUTER_APP_TITLE=CangjieCoder-Agent
```

## 实战测试建议

### 1. 本地/无远端模型测试

即使没有远端模型 API Key，也可以直接验证 agent 的 fallback 能力：

```bash
cd agent
cjpm run --run-args "--workspace /absolute/path/to/workspace --prompt 请分析当前仓颉工程，补充必要的构建和测试验证"
```

这条路径会验证：

- MCP 拉起
- 工具发现
- fallback 规划
- `build/test` 验证链路

### 2. 免费模型联调测试

如果你有 OpenRouter key，可以优先用 `openrouter/free` 做一次真实联调，再逐步替换为更强的 `:free` coding/reasoning 模型。

建议先试下面两类任务：

1. **诊断型任务**：分析当前仓颉工程结构并给出重构计划
2. **执行型任务**：在临时目录 bootstrap 示例项目并自动 build/test

### 3. 当前仓库内已做过的验证

本轮代码已在仓库内完成：

- `agent` 单元测试
- `service` 单元测试
- 根 workspace `cjpm build && cjpm test`
- agent 驱动 `project.bootstrap_json_parser + build + test` 的端到端流程验证

> 说明：模型密钥只在 `agent` 进程中使用，不需要配置到 `service`。
