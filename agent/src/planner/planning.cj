// 规划解析：plan 解析、回退计划、步骤归一化
package cangjiecoderagent.planner

import std.collection.*
import stdx.encoding.json.*
import cangjiecoderagent.common.*

public func allowedToolNames(toolsJson: String): Array<String> {
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

public func containsTool(allowedTools: Array<String>, tool: String): Bool {
    for (allowed in allowedTools) {
        if (allowed == tool) {
            return true
        }
    }
    return false
}

public func extractWorkspaceFiles(snapshot: String): Array<String> {
    let snapshotRoot = parseJsonObject(snapshot)
    let data = extractStructuredData(snapshotRoot)
    match (data.get("files")) {
        case Some(filesValue) =>
            return jsonArrayStrings(filesValue.asArray())
        case None =>
            return []
    }
}

public func normalizePlanSteps(steps: Array<PlannedToolCall>, allowedTools: Array<String>): Array<PlannedToolCall> {
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

const FALLBACK_README_PATH: String = "README.md"

func pruneFallbackSteps(steps: ArrayList<PlannedToolCall>): Unit {
    while (steps.size > MAX_PLAN_STEPS) {
        var removed = false
        var index: Int64 = 0
        while (index < steps.size) {
            let step = steps[index]
            if (step.tool == "workspace.read_file" && jsonField(step.arguments, "path") == FALLBACK_README_PATH) {
                steps.remove(at: index)
                removed = true
                break
            }
            index += 1
        }
        if (removed) {
            continue
        }

        index = 0
        while (index < steps.size) {
            if (steps[index].tool == "workspace.read_file") {
                steps.remove(at: index)
                removed = true
                break
            }
            index += 1
        }
        if (removed) {
            continue
        }
        steps.remove(at: steps.size - 1)
    }
}

public func extractTargetPathFromPrompt(prompt: String): String {
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

func extractPromptFilePath(prompt: String, workspaceFiles: Array<String>): String {
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

public func promptNeedsAnalysis(prompt: String): Bool {
    return containsAny(prompt, ["分析", "重构", "优化", "实现", "修复", "设计", "架构", "analyze", "refactor", "optimize", "implement", "fix", "design", "architecture"])
}

public func promptNeedsMutation(prompt: String): Bool {
    return containsAny(prompt, ["修改", "修复", "重构", "优化", "实现", "新增", "创建", "replace", "fix", "refactor", "optimize", "implement", "create", "edit"])
}

public func promptNeedsVerification(prompt: String): Bool {
    let normalized = prompt.toAsciiLower()
    return normalized.contains("build") ||
        normalized.contains("test") ||
        prompt.contains("构建") ||
        prompt.contains("测试") ||
        prompt.contains("验证")
}

// 判断用户提示词是否在请求创建新项目
func isNewProjectRequest(prompt: String): Bool {
    let normalized = prompt.toAsciiLower()
    if (normalized.contains("new project") || normalized.contains("bootstrap")) {
        return true
    }
    if (containsAny(prompt, ["新项目", "示例项目", "新建"])) {
        return true
    }
    if (prompt.contains("创建") && prompt.contains("项目")) {
        return true
    }
    return normalized.contains("jsonparser") || normalized.contains("json parser") ||
           normalized.contains("todo") || normalized.contains("calculator") ||
           (prompt.contains("计算器") || prompt.contains("待办"))
}

// 从提示词中推测最合适的示例项目 id
func detectExampleProjectId(prompt: String): String {
    let normalized = prompt.toAsciiLower()
    if (normalized.contains("todo") || prompt.contains("待办")) {
        return "todo_list"
    }
    if (normalized.contains("calc") || prompt.contains("计算器") || prompt.contains("表达式")) {
        return "calculator"
    }
    return "json_parser"
}

public func buildFallbackPlan(context: AgentPlanningContext): AgentPlan {
    let prompt = context.userPrompt
    let normalized = prompt.toAsciiLower()
    let needsMutation = promptNeedsMutation(prompt)
    let allowedTools = allowedToolNames(context.toolsJson)
    let workspaceFiles = extractWorkspaceFiles(context.workspaceSnapshot)
    let steps = ArrayList<PlannedToolCall>()

    if (isNewProjectRequest(prompt)) {
        let projectId = detectExampleProjectId(prompt)
        let arguments = JsonObject()
        arguments.put("project_id", JsonString(projectId))
        arguments.put("path", JsonString(extractTargetPathFromPrompt(prompt)))
        steps.add(PlannedToolCall("project.bootstrap", arguments, "Bootstrap the ${projectId} example project for a new-project style request."))
        return AgentPlan("Bootstrap a ${projectId} project and validate it locally.", steps.toArray())
    }

    steps.add(PlannedToolCall("workspace.list_files", JsonObject(), "Inspect the workspace layout before deeper actions."))
    if (workspaceFiles.contains(FALLBACK_README_PATH)) {
        steps.add(readFileStep(FALLBACK_README_PATH, "Read the workspace README to understand the project purpose and commands."))
    }
    if (workspaceFiles.contains("cjpm.toml")) {
        steps.add(readFileStep("cjpm.toml", "Inspect cjpm.toml to understand the package/workspace configuration."))
    }

    let candidateFile = extractPromptFilePath(prompt, workspaceFiles)
    if (!candidateFile.isEmpty() && promptNeedsAnalysis(prompt)) {
        if (containsTool(allowedTools, "cangjie.lsp_document_symbols")) {
            let lspArguments = JsonObject()
            lspArguments.put("path", JsonString(candidateFile))
            steps.add(PlannedToolCall("cangjie.lsp_document_symbols", lspArguments, "Inspect document-level symbols through the configured Cangjie LSP server."))
        }
        let arguments = JsonObject()
        arguments.put("path", JsonString(candidateFile))
        steps.add(PlannedToolCall("cangjie.analyze_file", arguments, "Analyze a representative Cangjie source file related to the request."))
    }

    if (needsMutation || normalized.contains("build") || prompt.contains("构建")) {
        steps.add(PlannedToolCall("workspace.run_build", JsonObject(), "Run a build because the request implies code changes or explicitly mentions compilation."))
    }
    if (needsMutation || normalized.contains("test") || prompt.contains("测试") || prompt.contains("验证")) {
        steps.add(PlannedToolCall("workspace.run_test", JsonObject(), "Run tests because the request explicitly mentions validation."))
    }
    pruneFallbackSteps(steps)
    return AgentPlan("Use local heuristics to inspect the workspace and execute requested validation.", steps.toArray())
}

public func parsePlan(reply: String, context: AgentPlanningContext): AgentPlan {
    let allowedTools = allowedToolNames(context.toolsJson)
    let jsonText = extractJsonObjectText(reply)
    if (!jsonText.trimAscii().isEmpty()) {
        try {
            let root = JsonValue.fromStr(jsonText).asObject()
            let parsedSteps = ArrayList<PlannedToolCall>()
            match (root.get("steps")) {
                case Some(stepsValue) =>
                    let steps = stepsValue.asArray()
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
    return AgentPlan(fallback.summary, if (normalizedFallback.isEmpty()) {
        [PlannedToolCall("workspace.list_files", JsonObject(), "Fallback to a safe workspace listing step.")]
    } else {
        normalizedFallback
    })
}
