package cangjiecoder

import std.collection.*
import std.convert.*
import std.env.*
import std.io.*
import stdx.encoding.json.*
import stdx.net.http.*

const WORKSPACE_COMMAND_OUTPUT_PREVIEW_LINES: Int64 = 20
let allowedWorkspaceCommands: Array<String> = ["cjpm", "cjc", "cjlint", "tree-sitter", "find", "grep"]

func jsonField(obj: JsonObject, key: String, fallback!: String = ""): String {
    match (obj.get(key)) {
        case Some(value) =>
            match (value.kind()) {
                case JsString => return value.asString().getValue()
                case _ => return value.toString()
            }
        case None =>
            return fallback
    }
}

func parseJsonObject(body: String): JsonObject {
    if (body.trimAscii().isEmpty()) {
        return JsonObject()
    }
    return JsonValue.fromStr(body).asObject()
}

func parseJsonIntField(obj: JsonObject, key: String, fallback!: Int64 = 0): Int64 {
    let raw = jsonField(obj, key)
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return fallback
    }
    try {
        return Int64.parse(trimmed)
    } catch (e: Exception) {
        return fallback
    }
}

func jsonStringArrayField(obj: JsonObject, key: String): Array<String> {
    match (obj.get(key)) {
        case Some(value) =>
            match (value.kind()) {
                case JsArray =>
                    let items = value.asArray()
                    let results = ArrayList<String>()
                    var index: Int64 = 0
                    while (index < items.size()) {
                        match (items.get(index)) {
                            case Some(itemValue) =>
                                match (itemValue.kind()) {
                                    case JsString => results.add(itemValue.asString().getValue())
                                    case _ => results.add(itemValue.toString())
                                }
                            case None => ()
                        }
                        index += 1
                    }
                    return results.toArray()
                case JsString =>
                    return [value.asString().getValue()]
                case _ =>
                    return [value.toString()]
            }
        case None =>
            return []
    }
}

func effectiveModelName(provider: String, model: String): String {
    return if (model.trimAscii().isEmpty()) { provider } else { model }
}

func providersJson(): String {
    let array = JsonArray()
    for (provider in builtinProviders()) {
        let item = JsonObject()
        item.put("name", JsonString(provider.name))
        item.put("displayName", JsonString(provider.displayName))
        item.put("baseUrl", JsonString(provider.baseUrl))
        item.put("apiKeyEnv", JsonString(provider.apiKeyEnv))
        item.put("defaultModel", JsonString(provider.defaultModel))
        array.add(item)
    }
    let root = JsonObject()
    root.put("providers", array)
    return root.toString()
}

func skillsJson(skills: Array<SkillRecord>): String {
    let array = JsonArray()
    for (skill in skills) {
        let item = JsonObject()
        item.put("id", JsonString(skill.id))
        item.put("name", JsonString(skill.name))
        item.put("description", JsonString(skill.description))
        item.put("preview", JsonString(skill.preview))
        item.put("path", JsonString(skill.path))
        array.add(item)
    }
    let root = JsonObject()
    root.put("skills", array)
    return root.toString()
}

func analysisJson(result: AnalysisResult): String {
    let root = JsonObject()
    root.put("engine", JsonString(result.engine))
    root.put("success", JsonBool(result.success))
    root.put("summary", JsonString(result.summary))
    root.put("output", JsonString(result.output))
    return root.toString()
}

func exampleProjectsJson(repoRoot: String): String {
    let array = JsonArray()
    for (project in listExampleProjects(repoRoot)) {
        let item = JsonObject()
        item.put("id", JsonString(project.id))
        item.put("name", JsonString(project.name))
        item.put("description", JsonString(project.description))
        item.put("templatePath", JsonString(project.templatePath))
        array.add(item)
    }
    let root = JsonObject()
    root.put("projects", array)
    return root.toString()
}

func lspStatusJson(status: LspStatus): String {
    let root = JsonObject()
    root.put("available", JsonBool(status.available))
    root.put("command", JsonString(status.command))
    root.put("summary", JsonString(status.summary))
    root.put("sourceHint", JsonString(status.sourceHint))
    return root.toString()
}

func lspProbeJson(result: LspProbeResult): String {
    let root = JsonObject()
    root.put("available", JsonBool(result.available))
    root.put("success", JsonBool(result.success))
    root.put("command", JsonString(result.command))
    root.put("summary", JsonString(result.summary))
    root.put("responsePreview", JsonString(result.responsePreview))
    return root.toString()
}

func jsonRpcResult(idJson: String, resultJson: String): String {
    return "{\"jsonrpc\":\"2.0\",\"id\":${idJson},\"result\":${resultJson}}"
}

func jsonRpcError(idJson: String, code: Int64, message: String): String {
    let error = JsonObject()
    error.put("code", JsonInt(code))
    error.put("message", JsonString(message))
    return "{\"jsonrpc\":\"2.0\",\"id\":${idJson},\"error\":${error.toString()}}"
}

func toolResultJson(ok: Bool, summary: String, data!: JsonValue = JsonObject()): String {
    let root = JsonObject()
    root.put("ok", JsonBool(ok))
    root.put("summary", JsonString(summary))
    root.put("data", data)
    return root.toString()
}

func toolMessageJson(ok: Bool, summary: String, message: String): String {
    let data = JsonObject()
    data.put("message", JsonString(message))
    return toolResultJson(ok, summary, data: data)
}

func toolCommandResultJson(command: String,
                           arguments: Array<String>,
                           workingDirectory: String,
                           status: Int64,
                           stdout: String,
                           stderr: String): String {
    let argsJson = JsonArray()
    for (arg in arguments) {
        argsJson.add(JsonString(arg))
    }
    let data = JsonObject()
    data.put("command", JsonString(command))
    data.put("arguments", argsJson)
    data.put("workingDirectory", JsonString(workingDirectory))
    data.put("exitCode", JsonInt(status))
    data.put("stdout", JsonString(shortPreview(stdout, maxLines: WORKSPACE_COMMAND_OUTPUT_PREVIEW_LINES)))
    data.put("stderr", JsonString(shortPreview(stderr, maxLines: WORKSPACE_COMMAND_OUTPUT_PREVIEW_LINES)))
    let ok = status == 0
    let summary = if (ok) {
        "Command succeeded: ${command}"
    } else {
        "Command failed: ${command}"
    }
    return toolResultJson(ok, summary, data: data)
}

func mcpToolCallResultJson(content: String): String {
    let toolResult = JsonValue.fromStr(content).asObject()
    let textBlocks = JsonArray()
    let textBlock = JsonObject()
    textBlock.put("type", JsonString("text"))
    textBlock.put("text", JsonString(content))
    textBlocks.add(textBlock)

    let isError = match (toolResult.get("ok")) {
        case Some(value) =>
            match (value.toString()) {
                case "true" => false
                case _ => true
            }
        case None =>
            false
    }

    let result = JsonObject()
    result.put("content", textBlocks)
    result.put("structuredContent", toolResult)
    result.put("isError", JsonBool(isError))
    return result.toString()
}

func providerReplySucceeded(reply: String): Bool {
    return !reply.startsWith("Missing API key:") && !reply.startsWith("Unknown provider:")
}

func astEditSucceeded(message: String): Bool {
    return !message.startsWith("tree-sitter unavailable") &&
        !message.contains("No AST node matched") &&
        !message.contains("Path does not exist") &&
        !message.contains("escapes repository root")
}

func analyzeCangjieFile(repoRoot: String, path: String): AnalysisResult {
    let fullPath = ensureWorkspacePath(repoRoot, path)
    let treeSitterCommand = getVariable("TREE_SITTER_CANGJIE") ?? "tree-sitter"
    let (treeOk, treeStdout, treeStderr) = runCommandWithCapturedOutput(treeSitterCommand,
        ["parse", fullPath],
        repoRoot)
    if (treeOk) {
        return AnalysisResult("tree-sitter", true, "Tree-sitter parse succeeded", shortPreview(treeStdout, maxLines: 12))
    }
    if (!treeStderr.trimAscii().isEmpty()) {
        return AnalysisResult("tree-sitter", false,
            "Tree-sitter parse failed. Configure TREE_SITTER_CANGJIE to point to a Cangjie-enabled tree-sitter CLI.",
            shortPreview(treeStderr, maxLines: 12))
    }

    let lintCommand = getVariable("CJLINT_COMMAND") ?? "cjlint"
    let (lintOk, lintStdout, lintStderr) = runCommandWithCapturedOutput(lintCommand, [fullPath], repoRoot)
    if (lintOk) {
        return AnalysisResult("cjlint", true, "cjlint completed", shortPreview(lintStdout, maxLines: 12))
    }
    if (!lintStdout.trimAscii().isEmpty() || !lintStderr.trimAscii().isEmpty()) {
        return AnalysisResult("cjlint", false, "cjlint reported diagnostics", shortPreview("${lintStdout}\n${lintStderr}", maxLines: 12))
    }

    let compileCommand = getVariable("CJC_COMMAND") ?? "cjc"
    let (compileOk, compileStdout, compileStderr) = runCommandWithCapturedOutput(compileCommand, [fullPath], repoRoot)
    if (compileOk) {
        return AnalysisResult("cjc", true, "cjc syntax check succeeded", shortPreview(compileStdout, maxLines: 12))
    }

    return AnalysisResult(
        "fallback",
        false,
        "No precise analyzer is configured. Install tree-sitter or the Cangjie toolchain and set TREE_SITTER_CANGJIE / CJLINT_COMMAND / CJC_COMMAND.",
        shortPreview("${compileStdout}\n${compileStderr}", maxLines: 12)
    )
}

func buildSystemPrompt(registry: SkillRegistry, userPrompt: String, analysis: String): String {
    let context = registry.buildPromptContext(userPrompt, limit: 3)
    let sections = ArrayList<String>()
    sections.add("You are CangjieCoder, a lightweight AI coding assistant focused on Cangjie projects.")
    sections.add("Prioritize Cangjie-specific guidance, use the local skill library before guessing, and keep edits surgical.")
    sections.add("When the task targets Cangjie code, prefer precise file context and analyzer output to reduce token usage.")
    if (!context.trimAscii().isEmpty()) {
        sections.add("Relevant local skills:\n${context}")
    }
    if (!analysis.trimAscii().isEmpty()) {
        sections.add("Analyzer context:\n${analysis}")
    }
    return String.join(sections.toArray(), delimiter: "\n\n")
}

func chatWithMemoryJson(repoRoot: String,
                        registry: SkillRegistry,
                        conversations: ConversationStore,
                        provider: String,
                        model: String,
                        prompt: String,
                        analyzePath: String,
                        sessionId: String): String {
    let session = conversations.getOrCreate(sessionId: sessionId)
    let analysis = if (analyzePath.trimAscii().isEmpty()) {
        ""
    } else {
        analyzeCangjieFile(repoRoot, analyzePath).output
    }
    var systemPrompt = buildSystemPrompt(registry, prompt, analysis)
    let historyPrompt = session.buildPrompt(limit: 6)
    if (!historyPrompt.trimAscii().isEmpty()) {
        systemPrompt = "${systemPrompt}\n\nRecent conversation turns:\n${historyPrompt}"
    }
    let reply = chatWithProvider(provider, model, systemPrompt, prompt)
    session.addTurn("user", prompt)
    session.addTurn("assistant", reply)

    let root = JsonObject()
    root.put("sessionId", JsonString(session.sessionId))
    root.put("provider", JsonString(provider))
    root.put("model", JsonString(effectiveModelName(provider, model)))
    root.put("systemPrompt", JsonString(systemPrompt))
    root.put("historyPrompt", JsonString(historyPrompt))
    root.put("reply", JsonString(reply))
    root.put("turnCount", JsonInt(session.turnCount))
    root.put("success", JsonBool(providerReplySucceeded(reply)))
    return root.toString()
}

func resolveWorkspaceCommandDirectory(repoRoot: String, path: String): String {
    let normalized = path.trimAscii()
    if (normalized.isEmpty()) {
        return repoRoot
    }
    return ensureWorkspacePath(repoRoot, normalized)
}

func workspaceListFilesJson(repoRoot: String, path: String, limit!: Int64 = 200): String {
    let startPath = resolveWorkspaceCommandDirectory(repoRoot, path)
    let (status, stdout, stderr) = runCommandDetailedOutput("find", [startPath, "-type", "f"], repoRoot)
    if (status != 0) {
        return toolCommandResultJson("find", [startPath, "-type", "f"], repoRoot, status, stdout, stderr)
    }

    let files = JsonArray()
    var count: Int64 = 0
    for (line in stdout.lines()) {
        let trimmed = line.trimAscii()
        if (trimmed.isEmpty()) {
            continue
        }
        if (count >= limit) {
            break
        }
        files.add(JsonString(workspaceRelativePath(repoRoot, trimmed)))
        count += 1
    }

    let data = JsonObject()
    data.put("path", JsonString(workspaceRelativePath(repoRoot, startPath)))
    data.put("count", JsonInt(count))
    data.put("files", files)
    return toolResultJson(true, "Listed workspace files", data: data)
}

func workspaceSearchTextJson(repoRoot: String, query: String, path: String, limit!: Int64 = 20): String {
    if (query.trimAscii().isEmpty()) {
        return toolMessageJson(false, "workspace.search_text requires a non-empty query", "query must not be empty")
    }

    let startPath = resolveWorkspaceCommandDirectory(repoRoot, path)
    // -R recursive, -n line numbers, -I ignore binary files, -F fixed-string search.
    let arguments = ["-R", "-n", "-I", "-F", query, startPath]
    let (status, stdout, stderr) = runCommandDetailedOutput("grep", arguments, repoRoot)
    if (status != 0 && status != 1) {
        return toolCommandResultJson("grep", arguments, repoRoot, status, stdout, stderr)
    }

    let matches = JsonArray()
    var count: Int64 = 0
    for (line in stdout.lines()) {
        let firstColon = match (line.indexOf(":")) {
            case Some(value) => value
            case None => continue
        }
        let secondColon = match (line.indexOf(":", firstColon + 1)) {
            case Some(value) => value
            case None => continue
        }
        let filePath = line[0..firstColon]
        let lineNumber = line[firstColon + 1..secondColon]
        let preview = line[secondColon + 1..line.size]
        var parsedLine: Int64 = 0
        try {
            parsedLine = Int64.parse(lineNumber)
        } catch (e: Exception) {
            parsedLine = 0
        }
        let item = JsonObject()
        item.put("path", JsonString(workspaceRelativePath(repoRoot, filePath)))
        item.put("line", JsonInt(parsedLine))
        item.put("preview", JsonString(preview))
        matches.add(item)
        count += 1
        if (count >= limit) {
            break
        }
    }

    let data = JsonObject()
    data.put("query", JsonString(query))
    data.put("path", JsonString(workspaceRelativePath(repoRoot, startPath)))
    data.put("count", JsonInt(count))
    data.put("matches", matches)
    return toolResultJson(true, if (count == 0) { "No workspace matches found" } else { "Found workspace text matches" }, data: data)
}

func isAllowedWorkspaceCommand(command: String): Bool {
    let normalized = command.trimAscii().toAsciiLower()
    for (allowed in allowedWorkspaceCommands) {
        if (normalized == allowed) {
            return true
        }
    }
    return false
}

func workspaceRunCommandJson(repoRoot: String,
                             command: String,
                             arguments: Array<String>,
                             path: String): String {
    let normalizedCommand = command.trimAscii()
    if (!isAllowedWorkspaceCommand(normalizedCommand)) {
        return toolMessageJson(false,
            "Command is not allowed for workspace.run_command",
            "Allowed commands: cjpm, cjc, cjlint, tree-sitter, find, grep")
    }

    let workingDirectory = resolveWorkspaceCommandDirectory(repoRoot, path)
    let (status, stdout, stderr) = runCommandDetailedOutput(normalizedCommand, arguments, workingDirectory)
    return toolCommandResultJson(normalizedCommand, arguments, workingDirectory, status, stdout, stderr)
}

func callMcpTool(repoRoot: String,
                 registry: SkillRegistry,
                 conversations: ConversationStore,
                 toolName: String,
                 args: JsonObject): String {
    try {
        match (toolName) {
            case "skills.search" =>
                let query = jsonField(args, "query")
                let matches = registry.search(query, limit: 8)
                let data = parseJsonObject(skillsJson(matches))
                return toolResultJson(true, "Skills search completed", data: data)
            case "workspace.read_file" =>
                let path = jsonField(args, "path")
                let fullPath = ensureWorkspacePath(repoRoot, path)
                let content = readTextFile(fullPath)
                let data = JsonObject()
                data.put("path", JsonString(workspaceRelativePath(repoRoot, fullPath)))
                data.put("content", JsonString(content))
                data.put("bytes", JsonInt(content.toArray().size))
                return toolResultJson(true, "Read workspace file", data: data)
            case "workspace.list_files" =>
                return workspaceListFilesJson(repoRoot,
                    jsonField(args, "path"),
                    limit: parseJsonIntField(args, "limit", fallback: 200))
            case "workspace.search_text" =>
                return workspaceSearchTextJson(repoRoot,
                    jsonField(args, "query"),
                    jsonField(args, "path"),
                    limit: parseJsonIntField(args, "limit", fallback: 20))
            case "workspace.replace_text" =>
                let path = jsonField(args, "path")
                let oldText = jsonField(args, "oldText")
                let newText = jsonField(args, "newText")
                let message = replaceExactText(repoRoot, path, oldText, newText)
                let ok = message.startsWith("updated ")
                return toolMessageJson(ok, if (ok) { "Updated workspace file text" } else { "Workspace text replacement rejected" }, message)
            case "workspace.run_build" =>
                return workspaceRunCommandJson(repoRoot, "cjpm", ["build"], jsonField(args, "path"))
            case "workspace.run_test" =>
                return workspaceRunCommandJson(repoRoot, "cjpm", ["test"], jsonField(args, "path"))
            case "workspace.run_command" =>
                return workspaceRunCommandJson(repoRoot,
                    jsonField(args, "command"),
                    jsonStringArrayField(args, "args"),
                    jsonField(args, "path"))
            case "cangjie.analyze_file" =>
                let path = jsonField(args, "path")
                let analysis = analyzeCangjieFile(repoRoot, path)
                let data = parseJsonObject(analysisJson(analysis))
                return toolResultJson(analysis.success, analysis.summary, data: data)
            case "project.list_examples" =>
                let data = parseJsonObject(exampleProjectsJson(repoRoot))
                return toolResultJson(true, "Listed example projects", data: data)
            case "project.bootstrap_json_parser" =>
                let path = jsonField(args, "path")
                let message = bootstrapJsonParserProject(repoRoot, path)
                let ok = message.startsWith("Bootstrapped ")
                return toolMessageJson(ok, if (ok) { "Bootstrapped JsonParser example" } else { "JsonParser bootstrap did not complete" }, message)
            case "conversation.start_session" =>
                let session = conversations.createSession()
                let data = JsonObject()
                data.put("sessionId", JsonString(session.sessionId))
                return toolResultJson(true, "Created conversation session", data: data)
            case "conversation.get_history" =>
                let history = parseJsonObject(conversations.historyJson(jsonField(args, "sessionId")))
                return toolResultJson(true, "Loaded conversation history", data: history)
            case "conversation.chat" =>
                let chat = parseJsonObject(chatWithMemoryJson(repoRoot,
                    registry,
                    conversations,
                    jsonField(args, "provider", fallback: "kimi"),
                    jsonField(args, "model"),
                    jsonField(args, "prompt"),
                    jsonField(args, "analyzePath"),
                    jsonField(args, "sessionId")))
                let ok = jsonField(chat, "success") == "true"
                return toolResultJson(ok, if (ok) { "Conversation turn completed" } else { "Conversation turn failed" }, data: chat)
            case "cangjie.lsp_status" =>
                let status = parseJsonObject(lspStatusJson(inspectLspStatus(repoRoot)))
                return toolResultJson(true, "Loaded Cangjie LSP status", data: status)
            case "cangjie.lsp_probe" =>
                let result = parseJsonObject(lspProbeJson(probeLspServer(repoRoot)))
                let ok = jsonField(result, "success") == "true"
                return toolResultJson(ok, if (ok) { "LSP probe succeeded" } else { "LSP probe did not complete cleanly" }, data: result)
            case "cangjie.edit_ast_node" =>
                let path = jsonField(args, "path")
                let nodeType = jsonField(args, "nodeType")
                let replacement = jsonField(args, "replacement")
                let index = parseJsonIntField(args, "index", fallback: 0)
                let message = editAstNode(repoRoot, path, nodeType, replacement, index: index)
                let ok = astEditSucceeded(message)
                return toolMessageJson(ok, if (ok) { "AST node edit completed" } else { "AST node edit failed" }, message)
            case _ =>
                return toolMessageJson(false, "Unknown MCP tool", "Unknown tool: ${toolName}")
        }
    } catch (e: Exception) {
        return toolMessageJson(false, "MCP tool execution failed", shortPreview(e.toString(), maxLines: 12))
    }
}

class McpRuntime {
    let repoRoot: String
    let registry: SkillRegistry
    let conversations: ConversationStore

    public init(repoRoot: String) {
        this.repoRoot = repoRoot
        this.registry = SkillRegistry(repoRoot)
        this.conversations = ConversationStore()
    }

    public func handleRequest(body: String): ?String {
        try {
            let request = parseJsonObject(body)
            let (hasId, idJson) = match (request.get("id")) {
                case Some(value) => (true, value.toString())
                case None => (false, "null")
            }
            let method = jsonField(request, "method")
            let params = match (request.get("params")) {
                case Some(value) => value.asObject()
                case None => JsonObject()
            }

            if (!hasId) {
                return None
            }

            match (method) {
                case "initialize" =>
                    let result = JsonObject()
                    let capabilities = JsonObject()
                    capabilities.put("tools", JsonObject())
                    capabilities.put("prompts", JsonObject())
                    capabilities.put("resources", JsonObject())
                    result.put("capabilities", capabilities)
                    let serverInfo = JsonObject()
                    serverInfo.put("name", JsonString("CangjieCoder"))
                    serverInfo.put("version", JsonString(APP_VERSION))
                    result.put("serverInfo", serverInfo)
                    return Some(jsonRpcResult(idJson, result.toString()))
                case "ping" =>
                    return Some(jsonRpcResult(idJson, "{\"pong\":true}"))
                case "notifications/initialized" =>
                    return Some(jsonRpcResult(idJson, "null"))
                case "tools/list" =>
                    return Some(jsonRpcResult(idJson, toolDefinitionsJson()))
                case "tools/call" =>
                    let toolName = jsonField(params, "name")
                    let toolArgs = match (params.get("arguments")) {
                        case Some(value) => value.asObject()
                        case None => JsonObject()
                    }
                    return Some(jsonRpcResult(idJson, mcpToolCallResultJson(callMcpTool(repoRoot, registry, conversations, toolName, toolArgs))))
                case _ =>
                    return Some(jsonRpcError(idJson, -32601, "Unsupported MCP method: ${method}"))
            }
        } catch (e: Exception) {
            return Some(jsonRpcError("null", -32700, "Failed to parse MCP request: ${shortPreview(e.toString(), maxLines: 4)}"))
        }
    }
}

const MCP_HEADER_DELIMITER: String = "\r\n\r\n"
const MCP_CONTENT_LENGTH_HEADER: String = "Content-Length:"
const STDIO_CHUNK_SIZE: Int64 = 4096

func encodeMcpFrame(body: String): String {
    return "${MCP_CONTENT_LENGTH_HEADER} ${body.toArray().size}${MCP_HEADER_DELIMITER}${body}"
}

func extractMcpBodies(raw: String): Array<String> {
    return extractLspBodies(raw)
}

func readStdioFrame(reader: ConsoleReader): ?String {
    var contentLength: Int64 = -1
    while (true) {
        match (reader.readln()) {
            case Some(line) =>
                let trimmed = line.trimAscii()
                if (trimmed.isEmpty()) {
                    break
                }
                if (trimmed.startsWith(MCP_CONTENT_LENGTH_HEADER)) {
                    let rawLength = trimmed[MCP_CONTENT_LENGTH_HEADER.size..trimmed.size].trimAscii()
                    try {
                        contentLength = Int64.parse(rawLength)
                    } catch (e: Exception) {
                        return None
                    }
                }
            case None =>
                return None
        }
    }

    if (contentLength < 0) {
        return None
    }

    var bodyBytes = Array<Byte>(contentLength, repeat: 0)
    var offset: Int64 = 0
    while (offset < contentLength) {
        let remaining = contentLength - offset
        let chunkSize = if (remaining > STDIO_CHUNK_SIZE) { STDIO_CHUNK_SIZE } else { remaining }
        var chunk = Array<Byte>(chunkSize, repeat: 0)
        let bytesRead = reader.read(chunk)
        if (bytesRead <= 0) {
            return None
        }
        var index: Int64 = 0
        while (index < bytesRead) {
            bodyBytes[offset + index] = chunk[index]
            index += 1
        }
        offset += bytesRead
    }
    return String.fromUtf8(bodyBytes)
}

func startMcpStdioServer(config: AppConfig): Unit {
    let runtime = McpRuntime(config.repoRoot)
    let reader = getStdIn()
    let writer = getStdOut()
    while (true) {
        match (readStdioFrame(reader)) {
            case Some(body) =>
                match (runtime.handleRequest(body)) {
                    case Some(response) =>
                        writer.write(encodeMcpFrame(response))
                        writer.flush()
                    case None => ()
                }
            case None =>
                break
        }
    }
}

func startServer(config: AppConfig): Unit {
    let runtime = McpRuntime(config.repoRoot)
    let server = ServerBuilder().addr(config.host).port(config.port).build()

    server.distributor.register("/health", {
        ctx =>
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body("{\"status\":\"ok\"}")
    })

    server.distributor.register("/providers", {
        ctx =>
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(providersJson())
    })

    server.distributor.register("/projects/examples", {
        ctx =>
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(exampleProjectsJson(config.repoRoot))
    })

    server.distributor.register("/skills", {
        ctx =>
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(skillsJson(runtime.registry.list(limit: 200)))
    })

    server.distributor.register("/skills/search", {
        ctx =>
        let request = parseJsonObject(StringReader(ctx.request.body).readToEnd())
        let query = jsonField(request, "query")
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(skillsJson(runtime.registry.search(query, limit: 8)))
    })

    server.distributor.register("/analyze", {
        ctx =>
        let request = parseJsonObject(StringReader(ctx.request.body).readToEnd())
        let path = jsonField(request, "path")
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(analysisJson(analyzeCangjieFile(config.repoRoot, path)))
    })

    server.distributor.register("/bootstrap/json-parser", {
        ctx =>
        let request = parseJsonObject(StringReader(ctx.request.body).readToEnd())
        let path = jsonField(request, "path")
        let root = JsonObject()
        root.put("message", JsonString(bootstrapJsonParserProject(config.repoRoot, path)))
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(root.toString())
    })

    server.distributor.register("/lsp/status", {
        ctx =>
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(lspStatusJson(inspectLspStatus(config.repoRoot)))
    })

    server.distributor.register("/lsp/probe", {
        ctx =>
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(lspProbeJson(probeLspServer(config.repoRoot)))
    })

    server.distributor.register("/conversations/start", {
        ctx =>
        let session = runtime.conversations.createSession()
        let root = JsonObject()
        root.put("sessionId", JsonString(session.sessionId))
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(root.toString())
    })

    server.distributor.register("/conversations/history", {
        ctx =>
        let request = parseJsonObject(StringReader(ctx.request.body).readToEnd())
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(runtime.conversations.historyJson(jsonField(request, "sessionId")))
    })

    server.distributor.register("/ast/edit", {
        ctx =>
        let request = parseJsonObject(StringReader(ctx.request.body).readToEnd())
        let root = JsonObject()
        root.put("message", JsonString(editAstNode(config.repoRoot,
            jsonField(request, "path"),
            jsonField(request, "nodeType"),
            jsonField(request, "replacement"),
            index: parseJsonIntField(request, "index", fallback: 0))))
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(root.toString())
    })

    server.distributor.register("/chat", {
        ctx =>
        let request = parseJsonObject(StringReader(ctx.request.body).readToEnd())
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(chatWithMemoryJson(config.repoRoot,
                runtime.registry,
                runtime.conversations,
                jsonField(request, "provider", fallback: "kimi"),
                jsonField(request, "model"),
                jsonField(request, "prompt"),
                jsonField(request, "analyzePath"),
                jsonField(request, "sessionId")))
    })

    server.distributor.register("/mcp", {
        ctx =>
        let body = StringReader(ctx.request.body).readToEnd()
        match (runtime.handleRequest(body)) {
            case Some(response) =>
                ctx.responseBuilder
                    .header("Content-Type", "application/json")
                    .body(response)
            case None =>
                ctx.responseBuilder
                    .body("")
        }
    })

    println("CangjieCoder server listening on http://${config.host}:${config.port}")
    server.serve()
}
