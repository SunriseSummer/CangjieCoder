package cangjiecoder

import std.collection.*
import std.convert.*
import std.env.*
import std.io.*
import stdx.encoding.json.*
import stdx.net.http.*

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
    return root.toString()
}

func callMcpTool(repoRoot: String,
                 registry: SkillRegistry,
                 conversations: ConversationStore,
                 toolName: String,
                 args: JsonObject): String {
    match (toolName) {
        case "skills.search" =>
            let query = jsonField(args, "query")
            return skillsJson(registry.search(query, limit: 8))
        case "workspace.read_file" =>
            let path = jsonField(args, "path")
            let content = readTextFile(ensureWorkspacePath(repoRoot, path))
            let root = JsonObject()
            root.put("path", JsonString(path))
            root.put("content", JsonString(content))
            return root.toString()
        case "workspace.replace_text" =>
            let path = jsonField(args, "path")
            let oldText = jsonField(args, "oldText")
            let newText = jsonField(args, "newText")
            let message = replaceExactText(repoRoot, path, oldText, newText)
            let root = JsonObject()
            root.put("message", JsonString(message))
            return root.toString()
        case "cangjie.analyze_file" =>
            let path = jsonField(args, "path")
            return analysisJson(analyzeCangjieFile(repoRoot, path))
        case "project.list_examples" =>
            return exampleProjectsJson(repoRoot)
        case "project.bootstrap_json_parser" =>
            let path = jsonField(args, "path")
            let root = JsonObject()
            root.put("message", JsonString(bootstrapJsonParserProject(repoRoot, path)))
            return root.toString()
        case "conversation.start_session" =>
            let session = conversations.createSession()
            let root = JsonObject()
            root.put("sessionId", JsonString(session.sessionId))
            return root.toString()
        case "conversation.get_history" =>
            return conversations.historyJson(jsonField(args, "sessionId"))
        case "conversation.chat" =>
            return chatWithMemoryJson(repoRoot,
                registry,
                conversations,
                jsonField(args, "provider", fallback: "kimi"),
                jsonField(args, "model"),
                jsonField(args, "prompt"),
                jsonField(args, "analyzePath"),
                jsonField(args, "sessionId"))
        case "cangjie.lsp_status" =>
            return lspStatusJson(inspectLspStatus(repoRoot))
        case "cangjie.lsp_probe" =>
            return lspProbeJson(probeLspServer(repoRoot))
        case "cangjie.edit_ast_node" =>
            let path = jsonField(args, "path")
            let nodeType = jsonField(args, "nodeType")
            let replacement = jsonField(args, "replacement")
            let index = parseJsonIntField(args, "index", fallback: 0)
            let root = JsonObject()
            root.put("message", JsonString(editAstNode(repoRoot, path, nodeType, replacement, index: index)))
            return root.toString()
        case _ =>
            let root = JsonObject()
            root.put("message", JsonString("Unknown tool: ${toolName}"))
            return root.toString()
    }
}

func handleMcpRequest(repoRoot: String,
                      registry: SkillRegistry,
                      conversations: ConversationStore,
                      body: String): String {
    let request = parseJsonObject(body)
    let idJson = match (request.get("id")) {
        case Some(value) => value.toString()
        case None => "null"
    }
    let method = jsonField(request, "method")
    let params = match (request.get("params")) {
        case Some(value) => value.asObject()
        case None => JsonObject()
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
            return jsonRpcResult(idJson, result.toString())
        case "ping" =>
            return jsonRpcResult(idJson, "{\"pong\":true}")
        case "notifications/initialized" =>
            return jsonRpcResult(idJson, "null")
        case "tools/list" =>
            return jsonRpcResult(idJson, toolDefinitionsJson())
        case "tools/call" =>
            let toolName = jsonField(params, "name")
            let toolArgs = match (params.get("arguments")) {
                case Some(value) => value.asObject()
                case None => JsonObject()
            }
            let content = callMcpTool(repoRoot, registry, conversations, toolName, toolArgs)
            let result = JsonObject()
            result.put("content", JsonString(content))
            result.put("isError", JsonBool(false))
            return jsonRpcResult(idJson, result.toString())
        case _ =>
            return jsonRpcError(idJson, -32601, "Unsupported MCP method: ${method}")
    }
}

func startServer(config: AppConfig): Unit {
    let registry = SkillRegistry(config.repoRoot)
    let conversations = ConversationStore()
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
            .body(skillsJson(registry.list(limit: 200)))
    })

    server.distributor.register("/skills/search", {
        ctx =>
        let request = parseJsonObject(StringReader(ctx.request.body).readToEnd())
        let query = jsonField(request, "query")
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(skillsJson(registry.search(query, limit: 8)))
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
        let session = conversations.createSession()
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
            .body(conversations.historyJson(jsonField(request, "sessionId")))
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
                registry,
                conversations,
                jsonField(request, "provider", fallback: "kimi"),
                jsonField(request, "model"),
                jsonField(request, "prompt"),
                jsonField(request, "analyzePath"),
                jsonField(request, "sessionId")))
    })

    server.distributor.register("/mcp", {
        ctx =>
        let body = StringReader(ctx.request.body).readToEnd()
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(handleMcpRequest(config.repoRoot, registry, conversations, body))
    })

    println("CangjieCoder server listening on http://${config.host}:${config.port}")
    server.serve()
}
