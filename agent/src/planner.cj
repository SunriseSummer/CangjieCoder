package cangjiecoderagent

import std.collection.*
import stdx.encoding.json.*

func extractJsonObjectText(text: String): String {
    let codeFence = "```"
    let fencedStart = match (text.indexOf(codeFence)) {
        case Some(value) => value
        case None => -1
    }
    if (fencedStart >= 0) {
        let fencedEnd = match (text.indexOf(codeFence, fencedStart + codeFence.size)) {
            case Some(value) => value
            case None => -1
        }
        if (fencedEnd > fencedStart) {
            let fencedBody = text[fencedStart + codeFence.size..fencedEnd]
            let nested = extractJsonObjectText(fencedBody)
            if (!nested.isEmpty()) {
                return nested
            }
        }
    }

    let start = match (text.indexOf("{")) {
        case Some(value) => value
        case None => return ""
    }
    // provider 可能会在 JSON 外层包一段解释文字，
    // 这里退而求其次地截取“首个左花括号到最后一个可达右花括号”。
    var end: Int64 = text.size - 1
    while (end >= start) {
        if (text[end..end + 1] == "}") {
            return text[start..end + 1]
        }
        end -= 1
    }
    return ""
}

func extractTargetPathFromPrompt(prompt: String): String {
    // 新建项目提示词常常直接把目标目录写进自然语言中，
    // 这里按常见中英文分隔符裁剪出 target/... 路径。
    let marker = "target/"
    let start = match (prompt.indexOf(marker)) {
        case Some(value) => value
        case None => return "target/generated-json-parser"
    }
    let delimiters = [" ", "\n", "\t", "，", ",", "。", "\"", "'"]
    var end = prompt.size
    for (delimiter in delimiters) {
        match (prompt.indexOf(delimiter, start)) {
            case Some(value) =>
                if (value > start && value < end) {
                    end = value
                }
            case None => ()
        }
    }
    return prompt[start..end]
}

func allowedToolNames(toolsJson: String): Array<String> {
    // 从 tools/list 结果中提取白名单，后续所有模型计划与本地回退步骤
    // 都必须经过这里约束，防止调用不存在或未暴露的工具。
    let root = parseJsonObject(toolsJson)
    match (root.get("tools")) {
        case Some(toolsValue) =>
            let names = ArrayList<String>()
            let tools = toolsValue.asArray()
            var index: Int64 = 0
            while (index < tools.size()) {
                match (tools.get(index)) {
                    case Some(toolValue) =>
                        let tool = toolValue.asObject()
                        let name = jsonField(tool, "name")
                        if (!name.trimAscii().isEmpty()) {
                            names.add(name)
                        }
                    case None => ()
                }
                index += 1
            }
            return names.toArray()
        case None =>
            return []
    }
}

func containsTool(allowedTools: Array<String>, tool: String): Bool {
    for (allowed in allowedTools) {
        if (allowed == tool) {
            return true
        }
    }
    return false
}

func extractWorkspaceFiles(snapshot: String): Array<String> {
    // list_files 的结构化数据里只关心 files 字段，
    // 单独抽出来能让后续启发式逻辑更简单。
    let snapshotRoot = parseJsonObject(snapshot)
    let data = extractStructuredData(snapshotRoot)
    match (data.get("files")) {
        case Some(filesValue) =>
            return jsonArrayStrings(filesValue.asArray())
        case None =>
            return []
    }
}

func normalizePlanSteps(steps: Array<PlannedToolCall>, allowedTools: Array<String>): Array<PlannedToolCall> {
    let results = ArrayList<PlannedToolCall>()
    let seenKeys = HashSet<String>()
    for (step in steps) {
        let tool = step.tool.trimAscii()
        if (tool.isEmpty() || !containsTool(allowedTools, tool)) {
            continue
        }
        let stepKey = "${tool}|${step.arguments.toString()}"
        if (seenKeys.contains(stepKey)) {
            continue
        }
        // 以“工具 + 参数”去重，避免模型在 replanning 时重复输出同一步，
        // 浪费有限的执行轮次与预算。
        seenKeys.add(stepKey)
        results.add(PlannedToolCall(tool, step.arguments, step.reason))
        if (results.size >= MAX_PLAN_STEPS) {
            break
        }
    }
    return results.toArray()
}

func readFileStep(path: String, reason: String): PlannedToolCall {
    let arguments = JsonObject()
    arguments.put("path", JsonString(path))
    return PlannedToolCall("workspace.read_file", arguments, reason)
}

func extractPromptFilePath(prompt: String, workspaceFiles: Array<String>): String {
    // 优先选择提示词中明确提到的 .cj 文件；
    // 如果没点名，再退化到工作区里的第一个 Cangjie 源文件。
    for (file in workspaceFiles) {
        if (file.endsWith(".cj") && prompt.contains(file)) {
            return file
        }
    }
    for (file in workspaceFiles) {
        if (file.endsWith(".cj")) {
            return file
        }
    }
    return ""
}

func promptNeedsAnalysis(prompt: String): Bool {
    return containsAny(prompt, ["分析", "重构", "优化", "实现", "修复", "设计", "架构", "analyze", "refactor", "optimize", "implement", "fix", "design", "architecture"])
}

func promptNeedsMutation(prompt: String): Bool {
    return containsAny(prompt, ["修改", "修复", "重构", "优化", "实现", "新增", "创建", "replace", "fix", "refactor", "optimize", "implement", "create", "edit"])
}

func promptNeedsVerification(prompt: String): Bool {
    let normalized = prompt.toAsciiLower()
    return normalized.contains("build") ||
        normalized.contains("test") ||
        prompt.contains("构建") ||
        prompt.contains("测试") ||
        prompt.contains("验证")
}

func buildFallbackPlan(context: AgentPlanningContext): AgentPlan {
    let prompt = context.userPrompt
    let normalized = prompt.toAsciiLower()
    let needsMutation = promptNeedsMutation(prompt)
    let workspaceFiles = extractWorkspaceFiles(context.workspaceSnapshot)
    let steps = ArrayList<PlannedToolCall>()

    if (normalized.contains("new project") ||
        normalized.contains("bootstrap") ||
        containsAny(prompt, ["新项目", "示例项目", "新建"]) ||
        (prompt.contains("创建") && prompt.contains("项目")) ||
        normalized.contains("jsonparser") ||
        normalized.contains("json parser")) {
        let arguments = JsonObject()
        arguments.put("path", JsonString(extractTargetPathFromPrompt(prompt)))
        // 当前仓库内唯一稳定维护的模板是 JsonParser 示例，
        // 因此“新项目”类请求优先走确定性的 bootstrap 快路径。
        steps.add(PlannedToolCall("project.bootstrap_json_parser", arguments, "Bootstrap the starter project for a new-project style request."))
        return AgentPlan("Bootstrap a starter project and validate it locally.", steps.toArray())
    }

    // 常规请求默认先看目录、README、cjpm.toml，
    // 把“先理解工作区再行动”固化为本地回退策略。
    steps.add(PlannedToolCall("workspace.list_files", JsonObject(), "Inspect the workspace layout before deeper actions."))
    if (workspaceFiles.contains("README.md")) {
        steps.add(readFileStep("README.md", "Read the workspace README to understand the project purpose and commands."))
    }
    if (workspaceFiles.contains("cjpm.toml")) {
        steps.add(readFileStep("cjpm.toml", "Inspect cjpm.toml to understand the package/workspace configuration."))
    }

    let candidateFile = extractPromptFilePath(prompt, workspaceFiles)
    if (!candidateFile.isEmpty() && promptNeedsAnalysis(prompt)) {
        let arguments = JsonObject()
        arguments.put("path", JsonString(candidateFile))
        // 选一个代表性源码文件做 analyze，通常比直接修改更稳，
        // 也能给后续模型轮次补充更精确的上下文。
        steps.add(PlannedToolCall("cangjie.analyze_file", arguments, "Analyze a representative Cangjie source file related to the request."))
    }

    if (needsMutation || normalized.contains("build") || prompt.contains("构建")) {
        steps.add(PlannedToolCall("workspace.run_build", JsonObject(), "Run a build because the request implies code changes or explicitly mentions compilation."))
    }
    if (needsMutation || normalized.contains("test") || prompt.contains("测试") || prompt.contains("验证")) {
        steps.add(PlannedToolCall("workspace.run_test", JsonObject(), "Run tests because the request explicitly mentions validation."))
    }
    return AgentPlan("Use local heuristics to inspect the workspace and execute requested validation.", steps.toArray())
}

func parsePlan(reply: String, context: AgentPlanningContext): AgentPlan {
    let allowedTools = allowedToolNames(context.toolsJson)
    let jsonText = extractJsonObjectText(reply)
    if (!jsonText.trimAscii().isEmpty()) {
        try {
            let root = JsonValue.fromStr(jsonText).asObject()
            let parsedSteps = ArrayList<PlannedToolCall>()
            match (root.get("steps")) {
                case Some(stepsValue) =>
                    let steps = stepsValue.asArray()
                    // 模型显式返回空数组时，视为“无需继续执行”的合法信号，
                    // 不再强行触发本地 fallback 计划。
                    if (steps.size() == 0) {
                        return AgentPlan(jsonField(root, "summary", fallback: "Model indicates no further work is required"), [])
                    }
                    var index: Int64 = 0
                    while (index < steps.size()) {
                        match (steps.get(index)) {
                            case Some(stepValue) =>
                                let step = stepValue.asObject()
                                let tool = jsonField(step, "tool")
                                let arguments = match (step.get("arguments")) {
                                    case Some(argumentsValue) => argumentsValue.asObject()
                                    case None => JsonObject()
                                }
                                parsedSteps.add(PlannedToolCall(tool, arguments, jsonField(step, "reason")))
                            case None => ()
                        }
                        index += 1
                    }
                case None => ()
            }
            let normalizedSteps = normalizePlanSteps(parsedSteps.toArray(), allowedTools)
            if (!normalizedSteps.isEmpty()) {
                return AgentPlan(jsonField(root, "summary", fallback: "Model-generated execution plan"), normalizedSteps)
            }
        } catch (e: Exception) {
            ()
        }
    }
    let fallback = buildFallbackPlan(context)
    let normalizedFallback = normalizePlanSteps(fallback.steps, allowedTools)
    // 即使模型输出完全不可用，也至少回退到一个安全的检查步骤，
    // 避免 runner 因空计划进入不可预期状态。
    return AgentPlan(fallback.summary, if (normalizedFallback.isEmpty()) {
        [PlannedToolCall("workspace.list_files", JsonObject(), "Fallback to a safe workspace listing step.")]
    } else {
        normalizedFallback
    })
}

func buildPlanPrompt(context: AgentPlanningContext): String {
    // 在提示词中显式注入上限，帮助模型把计划控制在可执行范围内，
    // 同时保留完成一次标准开发闭环所需的步骤数量。
    return """
You are the single-agent planner for CangjieCoder.

User request:
${context.userPrompt}

Available MCP tools (JSON):
${context.toolsJson}

Workspace snapshot (JSON):
${context.workspaceSnapshot}

Built-in example projects (JSON):
${context.exampleProjectsJson}

Return strict JSON only with this shape:
{
  "summary": "one sentence",
  "steps": [
    {
      "tool": "<tool_name_from_list>",
      "arguments": {},
      "reason": "why"
    }
  ]
}

Rules:
- choose at most ${MAX_PLAN_STEPS} steps
- use only tool names from the provided tool list
- if the user asks for a new project, you may use project.bootstrap_json_parser
- prefer reading configuration/docs or analyzing code before destructive changes
- include workspace.run_build / workspace.run_test when they are clearly needed
- do not wrap the JSON in markdown
"""
}

func buildReplanPrompt(userPrompt: String,
                       previousPlans: Array<AgentPlan>,
                       executions: Array<ToolExecution>,
                       context: AgentPlanningContext): String {
    let planLines = ArrayList<String>()
    for (plan in previousPlans) {
        planLines.add("- ${plan.summary}")
        for (step in plan.steps) {
            planLines.add("  - ${step.tool}: ${step.reason}")
        }
    }

    let executionLines = ArrayList<String>()
    for (execution in executions) {
        executionLines.add("- tool=${execution.tool}")
        executionLines.add("  ok=${execution.ok}")
        executionLines.add("  summary=${execution.summary}")
        if (!execution.preview.trimAscii().isEmpty()) {
            executionLines.add("  preview=${execution.preview}")
        }
    }

    // Replan prompts feed the model only compact summaries so later rounds stay
    // grounded in prior observations without replaying entire tool payloads.
    return """
You are continuing a CangjieCoder agent run using a reflect-plan-act-review loop.

Original user request:
${userPrompt}

Previous plan summaries:
${String.join(planLines.toArray(), delimiter: "\n")}

Observed tool executions:
${String.join(executionLines.toArray(), delimiter: "\n")}

Current workspace snapshot (JSON):
${context.workspaceSnapshot}

Available MCP tools (JSON):
${context.toolsJson}

Return strict JSON only with the same schema as before.

Rules:
- if the task is already complete, return {"summary":"done","steps":[]}
- prefer targeted next steps instead of repeating already executed steps
- if a previous step failed, focus on diagnosis, repair, or verification
- choose at most ${MAX_PLAN_STEPS} steps
- use only tool names from the provided tool list
- do not wrap the JSON in markdown
"""
}
