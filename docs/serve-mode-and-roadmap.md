# CangjieCoder `serve` 模式使用说明、集成方式与能力规划

本文面向项目负责人、使用者和后续开发者，回答以下问题：

1. `serve` 模式启动后，这个工具当前到底是什么形态，应该怎么用？
2. 它能不能接入 OpenCode、Cursor、VSCode Copilot 等外部工具？
3. 它自己能不能在一个仓颉项目目录里直接做 AI 开发、自动执行任务？
4. 当前已经能做什么，不能做什么？
5. 如果希望它演进成“可直接输入需求并自主完成开发任务”的工具，还需要补哪些模块？

---

## 1. 一句话结论

当前的 CangjieCoder **已经是一个可运行的本地 AI 开发服务骨架**，但它现在更准确的定位是：

- 一个面向仓颉项目的 **HTTP + MCP 风格工具服务**；
- 一个带有 **Skills 检索、模型调用、仓颉分析、会话记忆、LSP 探测、AST 编辑入口** 的后端；
- 一个适合被其他 AI 宿主工具调用的 **能力底座 / Agent Runtime 雏形**；
- 还**不是**一个“像 Cursor / Copilot Chat 那样开箱即用、内置完整任务规划与执行闭环的成熟 AI IDE Agent”。

也就是说：

- **现在可以作为服务接入别的 AI 工具链的一部分使用；**
- **现在也可以手工通过 HTTP/MCP 调它完成一些仓颉专项能力；**
- **但还不能独立做到“进入任意仓颉项目目录 -> 输入需求 -> 自动规划 -> 自动改代码 -> 自动运行测试 -> 自动迭代直到完成”的完整自治开发闭环。**

---

## 2. `serve` 模式启动后，当前是什么形态？

执行：

```bash
cjpm run --run-args "serve --repo /absolute/path/to/project --host 127.0.0.1 --port 8080"
```

或者在发布产物下直接运行：

```bash
./target/release/bin/main serve --repo /absolute/path/to/project --host 127.0.0.1 --port 8080
```

启动后，CangjieCoder 会在本地暴露一个服务，当前包含两类接口：

### 2.1 HTTP 业务接口

主要包括：

- `/health`
- `/providers`
- `/projects/examples`
- `/bootstrap/json-parser`
- `/skills`
- `/skills/search`
- `/analyze`
- `/lsp/status`
- `/lsp/probe`
- `/conversations/start`
- `/conversations/history`
- `/ast/edit`
- `/chat`

这些接口适合：

- 用 `curl` / Postman 手动调试；
- 被你自己的前端、插件、中间层服务调用；
- 快速验证 CangjieCoder 当前能力是否正常。

### 2.2 MCP 风格 JSON-RPC 接口

入口：

- `/mcp`

当前支持的方法包括：

- `initialize`
- `ping`
- `notifications/initialized`
- `tools/list`
- `tools/call`

当前暴露的工具包括：

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

并且 `tools/list` 已经返回 `inputSchema`，所以从“协议描述能力”上，它已经比最早那版更接近可被 AI 宿主自动发现和调用的工具服务。

---

## 3. 当前 `serve` 模式怎么使用？

## 3.1 最简单的用法：当成本地仓颉 AI 能力服务

适合开发者自己手动调：

### 查询仓颉 Skills

```bash
curl -X POST http://127.0.0.1:8080/skills/search \
  -H 'content-type: application/json' \
  -d '{"query":"struct mut http"}'
```

### 分析仓颉文件

```bash
curl -X POST http://127.0.0.1:8080/analyze \
  -H 'content-type: application/json' \
  -d '{"path":"src/main.cj"}'
```

### 发起带会话记忆的聊天

```bash
curl -X POST http://127.0.0.1:8080/chat \
  -H 'content-type: application/json' \
  -d '{
    "sessionId":"demo-session",
    "provider":"kimi",
    "prompt":"请分析这个仓颉项目结构并给出下一步建议"
  }'
```

### 查看会话历史

```bash
curl -X POST http://127.0.0.1:8080/conversations/history \
  -H 'content-type: application/json' \
  -d '{"sessionId":"demo-session"}'
```

### 做一次 AST 节点级替换

```bash
curl -X POST http://127.0.0.1:8080/ast/edit \
  -H 'content-type: application/json' \
  -d '{
    "path":"src/main.cj",
    "nodeType":"function_definition",
    "index":0,
    "replacement":"func demo(): Unit { println(\"hello\") }"
  }'
```

### 通过 MCP 工具方式调用

```bash
curl -X POST http://127.0.0.1:8080/mcp \
  -H 'content-type: application/json' \
  -d '{
    "jsonrpc":"2.0",
    "id":1,
    "method":"tools/list",
    "params":{}
  }'
```

---

## 3.2 第二种用法：作为“AI 宿主工具”的后端能力服务

也就是：

- 前端 IDE/编辑器/插件/命令行 Agent 负责：
  - 接收用户自然语言需求
  - 展示对话界面
  - 组织工具调用流程
  - 承担计划/确认/审批/交互体验
- CangjieCoder 负责：
  - 仓颉 Skills 检索
  - 仓颉代码分析
  - 仓颉 LSP 探测
  - AST 级编辑入口
  - 仓颉项目模板引导
  - 会话上下文拼装
  - 模型调用

这个方向是**当前最现实、也最适合第一阶段落地**的用法。

---

## 4. 能接入 OpenCode / Cursor / VSCode Copilot 吗？

## 4.1 先给结论

**从能力和协议方向看：现在已经可以通过 stdio MCP 方式接入支持外部 MCP Server 的宿主；但还没有做到对 OpenCode / Cursor / VSCode Copilot 等产品的“官方开箱即用适配”。**

更准确地说：

- **如果某个宿主支持自定义 MCP Server 或自定义 HTTP Tool Bridge，CangjieCoder 有机会接进去；**
- **但当前仓库还没有提供针对 OpenCode / Cursor / VSCode Copilot 的现成适配层、配置模板或安装说明；**
- **现在已经同时提供 HTTP `/mcp` 与 `mcp-stdio` 两种 MCP 入口，其中 `mcp-stdio` 更适合主流 MCP 客户端托管本地子进程。**

所以现在的状态不是“不能接”，而是：

> **协议和能力底座已经在往这个方向靠，但离“可直接接入主流 AI IDE 工具”还差一层到两层适配。**

---

## 4.2 对不同宿主，当前可以怎样理解

### A. 对支持自定义 MCP 的宿主

如果某个宿主支持：

- 配置外部 MCP server；
- 或允许通过代理把 HTTP MCP 转成它可识别的接入形式；

那么 CangjieCoder 当前已经具备以下有价值的基础：

- 工具列表可发现（`tools/list` + `inputSchema`）
- 工具调用入口已统一（`tools/call`）
- 会话记忆有基础实现
- 仓颉专用分析路径已接通

此时需要补的多半不是仓颉能力本身，而是**宿主适配层**。

### B. 对 Cursor / VSCode Copilot 这类 IDE 内置 Agent

这类工具通常更像完整产品能力，而不是一个通用“你给个 URL 我就能全部接进来”的原始壳。就当前 CangjieCoder 而言：

- **不能直接替代 Cursor / Copilot 本身；**
- **也没有现成插件把它接成这些产品里的一个外部仓颉工具源；**
- 但可以把它理解成未来可供这类工具消费的“仓颉专用后端能力服务”。

### C. 对 OpenCode / 自研 CLI Agent / 自研 IDE 插件

这类通常更容易接，因为你可以自己控制：

- tool calling 协议；
- HTTP/MCP 请求格式；
- 用户确认机制；
- 文件写入策略；
- 测试执行和回滚逻辑。

**所以从工程落地优先级上看：最先应该接的是“自研 Agent 壳 / 自研插件 / CLI 宿主”，其次再考虑通用对接 Cursor/Copilot 生态。**

---

## 4.3 如果要真正做到“可接入主流 MCP 客户端”，建议新增什么

至少补这几类能力：

1. **stdio 模式 MCP Server（已完成）**
   - 现在同时支持 HTTP `/mcp` 与 `mcp-stdio`
   - `mcp-stdio` 使用 `Content-Length` 帧读写 JSON-RPC，更适合 MCP 客户端直接托管

2. **更完整的 MCP 能力面**
   - 现在主要是 tools
   - 后续可补：
     - prompts
     - resources
     - sampling / model preference
     - streaming
     - cancellation
     - progress notifications

3. **宿主适配示例配置**
   - `docs/integrations/cursor.md`
   - `docs/integrations/vscode.md`
   - `docs/integrations/opencode.md`
   - 提供可复制配置片段和接入注意事项

4. **权限 / 审批 / 安全策略层**
   - 哪些工具可只读
   - 哪些工具可写代码
   - 哪些操作需要人工确认
   - 如何限制工作区范围

---

## 5. 现在它自己能不能直接做 AI 开发？

## 5.1 当前可以做到的“半自治”能力

如果你在某个仓颉项目目录启动 CangjieCoder：

```bash
cjpm run --run-args "serve --repo /absolute/path/to/your-cangjie-project"
```

它**已经可以作为一个仓颉开发服务底座**，完成以下一部分工作：

### 已经能做的

1. **理解仓颉相关知识**
   - 从本仓库 `.github/skills/*/SKILL.md` 检索本地知识
   - 自动拼接 Skills 上下文给模型

2. **读取和修改工作区文件**
   - 读文件：`workspace.read_file`
   - 精确文本替换：`workspace.replace_text`
   - AST 节点级替换：`cangjie.edit_ast_node`（依赖 tree-sitter）

3. **做仓颉专项分析**
   - `tree-sitter`
   - `cjlint`
   - `cjc`
   - LSP 状态与 probe

4. **维持短会话记忆**
   - 支持 `sessionId`
   - 能让连续两三轮请求保留上下文

5. **生成或引导第一个仓颉项目模板**
   - `JsonParser` 示例工程可直接复制出来继续开发

也就是说，**它已经具备“被一个上层 Agent 调用后完成仓颉专项子任务”的能力。**

---

## 5.2 当前还不能做到的“完整自治开发”

如果把“直接做 AI 开发”定义为：

> 我只输入一句需求，比如“在当前仓颉项目里实现一个 JsonParser，并补测试，跑通构建，修掉报错，再给出结果”，然后工具自己规划、执行、验证、反复迭代直到完成。

那么答案是：

**当前还不行，至少还不够完整。**

原因不是单点缺失，而是闭环能力还没补齐。

当前缺的关键不是“能不能调模型”，而是**自治任务系统**。

---

## 6. 为什么当前还不能成为完整 AI 开发 Agent？

因为完整 Agent 至少需要下面 6 个层级，而当前只完成了其中一部分：

### 6.1 任务规划层（当前缺）

需要能够把用户需求拆成计划，例如：

- 读取项目结构
- 判断当前代码基础
- 生成改动方案
- 分步写文件 / 改文件
- 运行编译和测试
- 读取报错
- 自动修复
- 形成最终总结

当前仓库还没有独立的 Planner / Task Graph / ReAct Loop 模块。

### 6.2 工具编排层（当前缺）

虽然已经有工具，但还缺：

- 自动决定何时调用哪个工具
- 连续多步调用工具并汇总结果
- 工具失败后的恢复和重试
- 多轮执行状态跟踪

当前是“工具已经有了”，但“自动调度器”还没有。

### 6.3 工作区执行层（当前部分缺）

完整 AI 开发要稳定执行：

- 文件搜索
- 批量编辑
- 新建文件
- 运行命令
- 构建
- 测试
- 收集日志
- 安全回滚

当前已有：

- 读文件
- 精确替换
- AST 替换

当前仍缺：

- 目录级搜索/批量扫描工具
- 命令执行工具对外暴露
- 构建/测试执行结果回流到 Agent
- 编辑冲突与补丁合并策略

### 6.4 持久上下文层（当前缺）

现在的会话记忆是进程内内存，只能算“短记忆”。

还缺：

- 持久化会话存储
- 项目画像（project profile）
- 长期记忆（代码规范、构建方式、常见问题）
- 任务恢复

### 6.5 真实 LSP 工作流层（当前缺）

现在有：

- LSP 检测
- LSP probe

还没有：

- 持久 LSP 会话
- hover
- definition
- references
- document symbols
- workspace symbols
- diagnostics 同步
- rename / code action

没有这些，就还达不到成熟 IDE Agent 的精度。

### 6.6 安全与交互治理层（当前缺）

完整自治开发通常还要有：

- 用户确认点
- 风险分级
- 可回滚 patch
- 只读/只写策略
- 测试不过时的停止策略
- 失败报告格式

当前尚未建立这套治理框架。

---

## 7. 如果要把它做成“项目内直接提需求并自主执行”的工具，需要开发哪些模块？

下面给出一个建议的模块拆分，可直接用于排期。

## 7.1 P0：把它做成“可被外部 Agent 稳定调用的仓颉后端”

目标：先成为可靠的仓颉能力服务，而不是一上来就做全自治。

当前这一层已经完成的能力包括：

1. **stdio MCP 模式**
2. **文件搜索 / 目录遍历 / grep 类工具**
   - `workspace.list_files`
   - `workspace.search_text`
3. **安全的命令执行工具**
   - `workspace.run_build`
   - `workspace.run_test`
   - `workspace.run_command`（受限白名单）
4. **结构化错误输出**
   - 工具错误统一收敛到 `ok` / `summary` / `data`
   - MCP `tools/call` 统一返回 `content` + `structuredContent` + `isError`
5. **统一工具结果模型**
6. **README + 接入说明文档补齐**

P0 完成后，CangjieCoder 已经可以比较自然地挂到自研 Agent 或支持外部 MCP 的宿主上；后续重点会转向更深的宿主适配、P1 半自治闭环，以及更完整的 MCP/LSP 能力。

---

## 7.2 P1：把它做成“半自治开发 Agent”

目标：用户给需求后，工具能自动执行一条有限闭环，但仍建议人工审阅。

建议新增：

1. **Planner / Executor 模块**
   - 任务拆分
   - 工具选择
   - 分步执行
2. **工作流状态机**
   - planned
   - running
   - waiting_confirmation
   - failed
   - completed
3. **补丁生成与应用机制**
4. **构建-测试-修复循环**
5. **会话持久化**
6. **任务日志 / 报告输出**

P1 完成后，基本就能做到：

> “在某个仓颉项目目录下，输入一个具体开发需求，由工具自动改代码、跑测试、给出结果。”

但这个阶段仍应保留人工确认。

---

## 7.3 P2：把它做成“更强的仓颉 IDE Agent”

目标：向 Cursor/Copilot 类体验靠近。

建议新增：

1. **持久 LSP Client**
   - hover / definition / references / rename / diagnostics
2. **更完整 tree-sitter 能力**
   - query
   - 结构化 AST diff
   - node insertion / deletion / move
3. **项目画像系统**
   - 依赖信息
   - 构建命令
   - 测试命令
   - 代码规范
4. **多模型路由**
   - 规划模型
   - 编辑模型
   - 审查模型
5. **审批与安全策略**
6. **IDE / 编辑器插件适配**

---

## 8. 推荐的版本规划

下面给一个比较务实的排期建议。

## V0.2（P0 已落地后的继续增强）

目标：把底座补稳。

建议范围：

- 宿主适配示例配置
- prompts/resources/streaming 等更完整 MCP 能力
- 更细的命令白名单与权限治理
- 持续补强端到端测试与集成测试

## V0.3

目标：半自治可用。

建议范围：

- Planner / Executor
- build-test-fix loop
- 持久会话
- 任务报告
- 项目画像

## V0.4

目标：仓颉精确开发能力增强。

建议范围：

- 持久 LSP client
- diagnostics / definition / symbols
- AST query/edit 增强
- 更多仓颉项目模板

## V0.5+

目标：对接外部 AI IDE / 形成完整 Agent 产品形态。

建议范围：

- Cursor / VSCode / OpenCode 适配层
- 审批与权限系统
- 可视化前端
- 任务历史和回放
- 多模型编排

---

## 9. 对“当前能做什么 / 未来能做什么”的管理者视角总结

## 当前已经能做的

- 作为本地服务启动在仓颉项目目录上
- 提供 HTTP / MCP 风格接口
- 让外部工具检索仓颉 Skills
- 调用模型并注入仓颉上下文
- 做基础会话记忆
- 做仓颉文件分析
- 探测 LSP 能力
- 做首版 AST 节点级编辑
- 引导生成 JsonParser 示例项目

## 当前还不能直接保证做到的

- 自动规划完整开发任务
- 自动跑构建/测试并迭代修复
- 持久记忆和任务恢复
- 完整 LSP 语义导航和重构
- IDE 开箱即用接入
- 可控的自治执行和审批闭环

## 未来扩展后可以做到的

- 作为标准 MCP Server 接入更多宿主
- 在仓颉项目中做“读代码 -> 改代码 -> 跑测试 -> 修复”的半自治开发
- 借助持久 LSP + AST + 项目画像提升仓颉代码编辑精度
- 发展成仓颉专用 AI IDE/Agent 后端，甚至独立产品

---

## 10. 最后的建议

如果目标是“尽快看到可用效果”，建议路线不要一开始就把 CangjieCoder 当成完整替代 Cursor/Copilot 的产品，而应按下面顺序推进：

1. **先把它做成稳定的仓颉 MCP / HTTP 能力底座**
2. **再补半自治开发闭环（规划 + 执行 + 测试）**
3. **最后再做主流 IDE / Agent 产品适配**

这样做的好处是：

- 研发路径清晰；
- 每个阶段都有可交付成果；
- 不会过早被 IDE 集成细节拖住；
- 仓颉专项能力能先沉淀成可复用后端资产。

如果后续需要，我建议下一篇文档可以继续写成：

- `docs/roadmap-v0.2-v0.5.md`：按版本拆任务清单；
- `docs/integration-architecture.md`：画出外部宿主 + CangjieCoder + 模型 + LSP + tree-sitter 的整体架构；
- `docs/agent-runtime-design.md`：专门设计 Planner / Executor / Tool Runtime / Memory / Approval 的内部模块边界。
