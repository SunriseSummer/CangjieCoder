package cangjiecoderagent

import std.collection.*
import std.convert.*
import std.env.*
import std.fs.*
import std.process.*
import stdx.encoding.json.*

const DEFAULT_PROVIDER: String = "kimi"
const DEFAULT_MODEL: String = "kimi-k2.5"
const MCP_HEADER_DELIMITER: String = "\r\n\r\n"
const MCP_CONTENT_LENGTH_HEADER: String = "Content-Length:"
const MAX_PLAN_STEPS: Int64 = 4
const MAX_TRANSCRIPT_LINES: Int64 = 12

struct AgentConfig {
    public AgentConfig(let workspaceRoot: String,
                       let serviceDir: String,
                       let provider: String,
                       let model: String,
                       let prompt: String) {}
}

struct PlannedToolCall {
    public PlannedToolCall(let tool: String,
                           let arguments: JsonObject,
                           let reason: String) {}
}

struct ToolExecution {
    public ToolExecution(let tool: String,
                         let ok: Bool,
                         let summary: String,
                         let preview: String) {}
}

func printUsage(): Unit {
    println("CangjieCoder Agent")
    println("")
    println("Usage:")
    println("  cangjiecoderagent --workspace PATH --prompt TEXT [--service-dir PATH] [--provider kimi|glm] [--model MODEL]")
}

func parseConfig(args: Array<String>): AgentConfig {
    var workspaceRoot = canonicalize(getWorkingDirectory().toString()).toString()
    var serviceDir = resolveDefaultServiceDir(workspaceRoot)
    var serviceDirExplicit = false
    var provider = DEFAULT_PROVIDER
    var model = DEFAULT_MODEL
    var prompt = ""
    var index = 0
    while (index < args.size) {
        let current = args[index]
        if (current == "--workspace" && index + 1 < args.size) {
            workspaceRoot = canonicalize(args[index + 1]).toString()
            index += 1
        } else if (current == "--service-dir" && index + 1 < args.size) {
            serviceDir = canonicalize(args[index + 1]).toString()
            serviceDirExplicit = true
            index += 1
        } else if (current == "--provider" && index + 1 < args.size) {
            provider = args[index + 1]
            index += 1
        } else if (current == "--model" && index + 1 < args.size) {
            model = args[index + 1]
            index += 1
        } else if (current == "--prompt" && index + 1 < args.size) {
            let promptParts = ArrayList<String>()
            var promptIndex = index + 1
            while (promptIndex < args.size) {
                promptParts.add(args[promptIndex])
                promptIndex += 1
            }
            prompt = String.join(promptParts.toArray(), delimiter: " ")
            break
        }
        index += 1
    }
    if (!serviceDirExplicit) {
        serviceDir = resolveDefaultServiceDir(workspaceRoot)
    }
    return AgentConfig(workspaceRoot, serviceDir, provider, model, prompt)
}

func resolveDefaultServiceDir(workspaceRoot: String): String {
    let directServiceDir = "${workspaceRoot}/service"
    if (exists(directServiceDir)) {
        return canonicalize(directServiceDir).toString()
    }

    let parentServiceDir = "${workspaceRoot}/../service"
    if (exists(parentServiceDir)) {
        return canonicalize(parentServiceDir).toString()
    }
    return directServiceDir
}

func jsonField(obj: JsonObject, key: String, fallback!: String = ""): String {
    match (obj.get(key)) {
        case Some(value) =>
            match (value.kind()) {
                case JsString => return value.asString().getValue()
                case _ => return value.toString()
            }
        case None => return fallback
    }
}

func parseJsonObject(body: String): JsonObject {
    if (body.trimAscii().isEmpty()) {
        return JsonObject()
    }
    return JsonValue.fromStr(body).asObject()
}

func shortPreview(text: String, maxLines!: Int64 = 8): String {
    let lines = ArrayList<String>()
    var count: Int64 = 0
    for (line in text.lines()) {
        if (line.trimAscii().isEmpty()) {
            continue
        }
        lines.add(line)
        count += 1
        if (count >= maxLines) {
            break
        }
    }
    return String.join(lines.toArray(), delimiter: "\n")
}

func shellQuote(text: String): String {
    return "'${text.replace("'", "'\"'\"'")}'"
}

func encodeMcpFrame(body: String): String {
    return "${MCP_CONTENT_LENGTH_HEADER} ${body.toArray().size}${MCP_HEADER_DELIMITER}${body}"
}

func extractMcpBodies(raw: String): Array<String> {
    let bodies = ArrayList<String>()
    var offset: Int64 = 0
    while (offset < raw.size) {
        let headerEnd = match (raw.indexOf(MCP_HEADER_DELIMITER, offset)) {
            case Some(value) => value
            case None => break
        }
        let headers = raw[offset..headerEnd]
        let lengthStart = match (headers.indexOf(MCP_CONTENT_LENGTH_HEADER)) {
            case Some(value) => value + MCP_CONTENT_LENGTH_HEADER.size
            case None => break
        }
        let lengthLineEnd = match (headers.indexOf("\r\n", lengthStart)) {
            case Some(value) => value
            case None => headers.size
        }
        let length = Int64.parse(headers[lengthStart..lengthLineEnd].trimAscii())
        let bodyStart = headerEnd + MCP_HEADER_DELIMITER.size
        let bodyEnd = bodyStart + length
        if (bodyEnd > raw.size) {
            break
        }
        bodies.add(raw[bodyStart..bodyEnd])
        offset = bodyEnd
    }
    return bodies.toArray()
}

func buildJsonRpcRequest(id: Int64, method: String, params: JsonValue): String {
    let root = JsonObject()
    root.put("jsonrpc", JsonString("2.0"))
    root.put("id", JsonInt(id))
    root.put("method", JsonString(method))
    root.put("params", params)
    return root.toString()
}

func resolveServiceCommand(serviceDir: String, workspaceRoot: String): String {
    let releaseBinary = "${serviceDir}/target/release/bin/main"
    let debugBinary = "${serviceDir}/target/debug/bin/main"
    let command = if (exists(releaseBinary)) {
        shellQuote(releaseBinary)
    } else if (exists(debugBinary)) {
        shellQuote(debugBinary)
    } else {
        let runArgs = shellQuote("mcp-stdio --repo ${workspaceRoot}")
        return "cd ${shellQuote(serviceDir)} && printf '%s' __PAYLOAD__ | cjpm run --run-args ${runArgs}"
    }
    return "cd ${shellQuote(serviceDir)} && printf '%s' __PAYLOAD__ | ${command} mcp-stdio --repo ${shellQuote(workspaceRoot)}"
}

func invokeMcp(config: AgentConfig, request: String): JsonObject {
    let initialize = buildJsonRpcRequest(1, "initialize", JsonObject())
    let payload = "${encodeMcpFrame(initialize)}${encodeMcpFrame(request)}"
    let commandTemplate = resolveServiceCommand(config.serviceDir, config.workspaceRoot)
    let script = commandTemplate.replace("__PAYLOAD__", shellQuote(payload))
    let (status, stdoutBytes, stderrBytes) = executeWithOutput("bash",
        ["-lc", script],
        workingDirectory: Path(config.serviceDir),
        stdOut: Pipe,
        stdErr: Pipe)
    let stdout = String.fromUtf8(stdoutBytes)
    let stderr = String.fromUtf8(stderrBytes)
    if (status != 0) {
        throw IllegalArgumentException("service invocation failed: ${shortPreview(stderr, maxLines: 8)}")
    }
    let bodies = extractMcpBodies(stdout)
    if (bodies.isEmpty()) {
        throw IllegalArgumentException("service returned no MCP response: ${shortPreview(stderr, maxLines: 8)}")
    }
    return parseJsonObject(bodies[bodies.size - 1])
}

func listTools(config: AgentConfig): String {
    let response = invokeMcp(config, buildJsonRpcRequest(2, "tools/list", JsonObject()))
    return jsonField(response, "result")
}

func callTool(config: AgentConfig, name: String, arguments: JsonObject): JsonObject {
    let params = JsonObject()
    params.put("name", JsonString(name))
    params.put("arguments", arguments)
    let response = invokeMcp(config, buildJsonRpcRequest(2, "tools/call", params))
    let result = parseJsonObject(jsonField(response, "result", fallback: "{}"))
    return parseJsonObject(jsonField(result, "structuredContent", fallback: "{}"))
}

func callConversation(config: AgentConfig, prompt: String): String {
    let args = JsonObject()
    args.put("provider", JsonString(config.provider))
    args.put("model", JsonString(config.model))
    args.put("prompt", JsonString(prompt))
    let result = callTool(config, "conversation.chat", args)
    let data = parseJsonObject(jsonField(result, "data", fallback: "{}"))
    return jsonField(data, "reply")
}

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

func parsePlan(reply: String, originalPrompt: String): Array<PlannedToolCall> {
    let jsonText = extractJsonObjectText(reply)
    if (!jsonText.trimAscii().isEmpty()) {
        try {
            let root = JsonValue.fromStr(jsonText).asObject()
            match (root.get("steps")) {
                case Some(stepsValue) =>
                    let steps = stepsValue.asArray()
                    let parsed = ArrayList<PlannedToolCall>()
                    var index: Int64 = 0
                    while (index < steps.size() && parsed.size < MAX_PLAN_STEPS) {
                        match (steps.get(index)) {
                            case Some(stepValue) =>
                                let step = stepValue.asObject()
                                let tool = jsonField(step, "tool")
                                if (!tool.trimAscii().isEmpty()) {
                                    let args = match (step.get("arguments")) {
                                        case Some(argumentsValue) => argumentsValue.asObject()
                                        case None => JsonObject()
                                    }
                                    parsed.add(PlannedToolCall(tool, args, jsonField(step, "reason")))
                                }
                            case None => ()
                        }
                        index += 1
                    }
                    if (!parsed.isEmpty()) {
                        return parsed.toArray()
                    }
                case None => ()
            }
        } catch (e: Exception) {
            ()
        }
    }
    return fallbackPlan(originalPrompt)
}

func fallbackPlan(prompt: String): Array<PlannedToolCall> {
    let normalized = prompt.toAsciiLower()
    let steps = ArrayList<PlannedToolCall>()
    if (normalized.contains("new project") ||
        normalized.contains("新项目") ||
        normalized.contains("bootstrap") ||
        normalized.contains("jsonparser") ||
        normalized.contains("json parser") ||
        prompt.contains("示例项目") ||
        prompt.contains("新建") ||
        (prompt.contains("创建") && prompt.contains("项目"))) {
        let args = JsonObject()
        args.put("path", JsonString(extractTargetPathFromPrompt(prompt)))
        steps.add(PlannedToolCall("project.bootstrap_json_parser", args, "Bootstrap the starter project when the request sounds like a new project task."))
        return steps.toArray()
    }
    if (normalized.contains("build") || prompt.contains("构建")) {
        steps.add(PlannedToolCall("workspace.run_build", JsonObject(), "Run build when the request emphasizes compilation."))
    }
    if (normalized.contains("test") || prompt.contains("测试")) {
        steps.add(PlannedToolCall("workspace.run_test", JsonObject(), "Run tests when the request emphasizes verification."))
    }
    if (!steps.isEmpty()) {
        return steps.toArray()
    }
    steps.add(PlannedToolCall("workspace.list_files", JsonObject(), "Capture the workspace snapshot before making decisions."))
    return steps.toArray()
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

func stepToolName(step: PlannedToolCall): String {
    return step.tool.trimAscii()
}

func isMutatingTool(tool: String): Bool {
    return tool == "workspace.replace_text" || tool == "cangjie.edit_ast_node" || tool == "project.bootstrap_json_parser"
}

func appendValidationSteps(steps: Array<PlannedToolCall>): Array<PlannedToolCall> {
    let results = ArrayList<PlannedToolCall>()
    var requiresValidation = false
    var hasBuild = false
    var hasTest = false
    var validationPath = "."
    for (step in steps) {
        let tool = stepToolName(step)
        results.add(step)
        if (isMutatingTool(tool)) {
            requiresValidation = true
            if (tool == "project.bootstrap_json_parser") {
                let bootstrapPath = jsonField(step.arguments, "path")
                if (!bootstrapPath.trimAscii().isEmpty()) {
                    validationPath = bootstrapPath
                }
            }
        }
        if (tool == "workspace.run_build") {
            hasBuild = true
        }
        if (tool == "workspace.run_test") {
            hasTest = true
        }
    }
    if (requiresValidation && !hasBuild) {
        let args = JsonObject()
        args.put("path", JsonString(validationPath))
        results.add(PlannedToolCall("workspace.run_build", args, "Automatically validate a mutating step with cjpm build."))
    }
    if (requiresValidation && !hasTest) {
        let args = JsonObject()
        args.put("path", JsonString(validationPath))
        results.add(PlannedToolCall("workspace.run_test", args, "Automatically validate a mutating step with cjpm test."))
    }
    return results.toArray()
}

func buildPlanPrompt(userPrompt: String, toolsJson: String, workspaceSnapshot: String, exampleProjectsJson: String): String {
    return """
You are the single-agent planner for CangjieCoder.

User request:
${userPrompt}

Available MCP tools (JSON):
${toolsJson}

Workspace snapshot (JSON):
${workspaceSnapshot}

Built-in example projects (JSON):
${exampleProjectsJson}

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
- include workspace.run_build / workspace.run_test when they are clearly needed
- do not wrap the JSON in markdown
"""
}

func formatExecution(result: JsonObject, tool: String): ToolExecution {
    let ok = jsonField(result, "ok", fallback: "false") == "true"
    let summary = jsonField(result, "summary")
    let data = parseJsonObject(jsonField(result, "data", fallback: "{}"))
    return ToolExecution(tool, ok, summary, shortPreview(data.toString(), maxLines: MAX_TRANSCRIPT_LINES))
}

func buildFinalPrompt(userPrompt: String, executions: Array<ToolExecution>): String {
    let lines = ArrayList<String>()
    for (execution in executions) {
        lines.add("tool=${execution.tool}")
        lines.add("ok=${execution.ok}")
        lines.add("summary=${execution.summary}")
        lines.add("preview=${execution.preview}")
        lines.add("")
    }
    return """
The user request was:
${userPrompt}

Tool execution transcript:
${String.join(lines.toArray(), delimiter: "\n")}

Please provide a concise Chinese status report that includes:
1. what was executed
2. whether it succeeded
3. important outputs or failures
4. the next recommended step
"""
}

func buildLocalFinalSummary(executions: Array<ToolExecution>): String {
    let lines = ArrayList<String>()
    lines.add("模型总结不可用，已退化为本地执行摘要：")
    for (execution in executions) {
        lines.add("- ${execution.tool}: ${if (execution.ok) { "成功" } else { "失败" }} / ${execution.summary}")
        if (!execution.preview.trimAscii().isEmpty()) {
            lines.add("  ${execution.preview}")
        }
    }
    lines.add("建议：如需模型生成更完整的重构/实现说明，请在可访问 Moonshot API 的环境下重新运行。")
    return String.join(lines.toArray(), delimiter: "\n")
}

main(args: Array<String>): Int64 {
    let config = parseConfig(args)
    if (config.prompt.trimAscii().isEmpty()) {
        printUsage()
        return 1
    }

    let toolsJson = listTools(config)
    let workspaceSnapshot = callTool(config, "workspace.list_files", JsonObject()).toString()
    let exampleProjects = callTool(config, "project.list_examples", JsonObject()).toString()
    let planReply = callConversation(config, buildPlanPrompt(config.prompt, toolsJson, workspaceSnapshot, exampleProjects))
    let steps = appendValidationSteps(parsePlan(planReply, config.prompt))

    println("[plan]")
    for (step in steps) {
        println("- ${step.tool}: ${step.reason}")
    }

    let executions = ArrayList<ToolExecution>()
    var allOk = true
    for (step in steps) {
        let result = callTool(config, step.tool, step.arguments)
        let execution = formatExecution(result, step.tool)
        executions.add(execution)
        println("[tool] ${execution.tool} => ${execution.summary}")
        if (!execution.preview.trimAscii().isEmpty()) {
            println(execution.preview)
        }
        if (!execution.ok) {
            allOk = false
        }
    }

    let remoteFinalReply = callConversation(config, buildFinalPrompt(config.prompt, executions.toArray()))
    let finalReply = if (remoteFinalReply.startsWith("Provider request failed:") ||
        remoteFinalReply.startsWith("Missing API key:") ||
        remoteFinalReply.startsWith("Unsupported provider:")) {
        buildLocalFinalSummary(executions.toArray())
    } else {
        remoteFinalReply
    }
    println("\n[final]\n${finalReply}")
    return if (allOk) { 0 } else { 1 }
}
