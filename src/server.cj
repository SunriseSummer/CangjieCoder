package cangjiecoder

import std.collection.*
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

func jsonRpcResult(idJson: String, resultJson: String): String {
    return "{\"jsonrpc\":\"2.0\",\"id\":${idJson},\"result\":${resultJson}}"
}

func jsonRpcError(idJson: String, code: Int64, message: String): String {
    let error = JsonObject()
    error.put("code", JsonInt(code))
    error.put("message", JsonString(message))
    return "{\"jsonrpc\":\"2.0\",\"id\":${idJson},\"error\":${error.toString()}}"
}

func availableToolsJson(): String {
    let tools = JsonArray()

    let searchSkills = JsonObject()
    searchSkills.put("name", JsonString("skills.search"))
    searchSkills.put("description", JsonString("Search built-in Cangjie skills stored in .github/skills."))
    tools.add(searchSkills)

    let readFile = JsonObject()
    readFile.put("name", JsonString("workspace.read_file"))
    readFile.put("description", JsonString("Read a file inside the repository root."))
    tools.add(readFile)

    let replaceText = JsonObject()
    replaceText.put("name", JsonString("workspace.replace_text"))
    replaceText.put("description", JsonString("Replace exactly one matched text block inside an existing file."))
    tools.add(replaceText)

    let analyze = JsonObject()
    analyze.put("name", JsonString("cangjie.analyze_file"))
    analyze.put("description", JsonString("Run tree-sitter/cjlint/cjc based analysis for a Cangjie source file."))
    tools.add(analyze)

    let root = JsonObject()
    root.put("tools", tools)
    return root.toString()
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

func callMcpTool(repoRoot: String, registry: SkillRegistry, toolName: String, args: JsonObject): String {
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
        case _ =>
            let root = JsonObject()
            root.put("message", JsonString("Unknown tool: ${toolName}"))
            return root.toString()
    }
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

func handleMcpRequest(repoRoot: String, registry: SkillRegistry, body: String): String {
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
            result.put("capabilities", capabilities)
            let serverInfo = JsonObject()
            serverInfo.put("name", JsonString("CangjieCoder"))
            serverInfo.put("version", JsonString("0.1.0"))
            result.put("serverInfo", serverInfo)
            return jsonRpcResult(idJson, result.toString())
        case "tools/list" =>
            return jsonRpcResult(idJson, availableToolsJson())
        case "tools/call" =>
            let toolName = jsonField(params, "name")
            let toolArgs = match (params.get("arguments")) {
                case Some(value) => value.asObject()
                case None => JsonObject()
            }
            let content = callMcpTool(repoRoot, registry, toolName, toolArgs)
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

    server.distributor.register("/chat", {
        ctx =>
        let request = parseJsonObject(StringReader(ctx.request.body).readToEnd())
        let provider = jsonField(request, "provider", fallback: "kimi")
        let model = jsonField(request, "model")
        let prompt = jsonField(request, "prompt")
        let analyzePath = jsonField(request, "analyzePath")
        let analysis = if (analyzePath.trimAscii().isEmpty()) {
            ""
        } else {
            analyzeCangjieFile(config.repoRoot, analyzePath).output
        }
        let systemPrompt = buildSystemPrompt(registry, prompt, analysis)
        let reply = chatWithProvider(provider, model, systemPrompt, prompt)
        let root = JsonObject()
        root.put("provider", JsonString(provider))
        root.put("model", JsonString(if (model.trimAscii().isEmpty()) { provider } else { model }))
        root.put("systemPrompt", JsonString(systemPrompt))
        root.put("reply", JsonString(reply))
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(root.toString())
    })

    server.distributor.register("/mcp", {
        ctx =>
        let body = StringReader(ctx.request.body).readToEnd()
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(handleMcpRequest(config.repoRoot, registry, body))
    })

    println("CangjieCoder server listening on http://${config.host}:${config.port}")
    server.serve()
}
