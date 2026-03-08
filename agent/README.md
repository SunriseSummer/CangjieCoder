# CangjieCoder Agent

`agent/` 是首个可跑通的单智能体应用。它会：

1. 通过 stdio MCP 拉起并调用 `service`
2. 读取工具列表和工作区快照
3. 使用 `conversation.chat`（默认 Kimi 2.5）生成 JSON 计划
4. 逐步执行 MCP 工具
5. 对修改型操作自动补充 `build/test` 验证，并输出最终总结

## 运行

```bash
cd agent
cjpm run --run-args "--workspace /absolute/path/to/workspace --prompt 在当前仓颉项目中分析问题并执行必要修改"
```

可选参数：

- `--service-dir /absolute/path/to/CangjieCoder/service`
- `--provider kimi|glm`
- `--model kimi-k2.5`
- `--prompt ...`

默认会优先调用 `../service/target/release/bin/main`；如果该二进制尚未构建，则回退为在 `service/` 目录下执行 `cjpm run --run-args "mcp-stdio ..."`。
