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

// 判断用户提示词是否在请求创建新项目（使用 cjpm init 初始化）
func isNewProjectRequest(prompt: String): Bool {
    let normalized = prompt.toAsciiLower()
    if (normalized.contains("new project") || normalized.contains("init")) {
        return true
    }
    return containsAny(prompt, ["新项目", "新建项目", "创建项目", "初始化项目"])
}

// 判断是否需要优先查阅技能文档
func promptNeedsSkills(prompt: String): Bool {
    return containsAny(prompt, [
        "怎么写", "怎样写", "如何写", "用法", "示例", "教程",
        "how to", "example", "tutorial", "usage",
        "JSON", "json", "HTTP", "http", "enum", "class", "struct",
        "泛型", "接口", "模式匹配", "并发", "异常",
        "generic", "interface", "pattern", "concurrent", "exception"
    ])
}

public func buildFallbackPlan(context: AgentPlanningContext): AgentPlan {
    let prompt = context.userPrompt
    let normalized = prompt.toAsciiLower()
    let needsMutation = promptNeedsMutation(prompt)
    let allowedTools = allowedToolNames(context.toolsJson)
    let workspaceFiles = extractWorkspaceFiles(context.workspaceSnapshot)
    let steps = ArrayList<PlannedToolCall>()

    // 新建项目：使用 cjpm init 创建然后进行构建验证
    if (isNewProjectRequest(prompt)) {
        let initArgs = JsonObject()
        initArgs.put("command", JsonString("cjpm init"))
        steps.add(PlannedToolCall("workspace.run_command", initArgs, "Initialize a new Cangjie project with cjpm init."))
        steps.add(PlannedToolCall("workspace.run_build", JsonObject(), "Build the newly initialized project to verify it compiles."))
        return AgentPlan("Initialize a new Cangjie project with cjpm init and verify the build.", steps.toArray())
    }

    // 需要查阅技能文档时，在工作区概览之前先搜索相关技能
    if (promptNeedsSkills(prompt)) {
        let skillArgs = JsonObject()
        skillArgs.put("query", JsonString(prompt))
        steps.add(PlannedToolCall("skills.search", skillArgs, "Search Cangjie skills for relevant language features and patterns."))
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
