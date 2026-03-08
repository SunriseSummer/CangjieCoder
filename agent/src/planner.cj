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

func buildFallbackPlan(context: AgentPlanningContext): AgentPlan {
    let prompt = context.userPrompt
    let normalized = prompt.toAsciiLower()
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
        steps.add(PlannedToolCall("project.bootstrap_json_parser", arguments, "Bootstrap the starter project for a new-project style request."))
        return AgentPlan("Bootstrap a starter project and validate it locally.", steps.toArray())
    }

    steps.add(PlannedToolCall("workspace.list_files", JsonObject(), "Inspect the workspace layout before deeper actions."))
    if (workspaceFiles.contains("README.md")) {
        steps.add(readFileStep("README.md", "Read the workspace README to understand the project purpose and commands."))
    }
    if (workspaceFiles.contains("cjpm.toml")) {
        steps.add(readFileStep("cjpm.toml", "Inspect cjpm.toml to understand the package/workspace configuration."))
    }

    let candidateFile = extractPromptFilePath(prompt, workspaceFiles)
    if (!candidateFile.isEmpty() &&
        containsAny(prompt, ["分析", "重构", "优化", "analyze", "refactor", "optimize", "实现", "修复"])) {
        let arguments = JsonObject()
        arguments.put("path", JsonString(candidateFile))
        steps.add(PlannedToolCall("cangjie.analyze_file", arguments, "Analyze a representative Cangjie source file related to the request."))
    }

    if (normalized.contains("build") || prompt.contains("构建")) {
        steps.add(PlannedToolCall("workspace.run_build", JsonObject(), "Run a build because the request explicitly mentions compilation."))
    }
    if (normalized.contains("test") || prompt.contains("测试") || prompt.contains("验证")) {
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

func buildPlanPrompt(context: AgentPlanningContext): String {
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
      "tool": "workspace.list_files",
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
