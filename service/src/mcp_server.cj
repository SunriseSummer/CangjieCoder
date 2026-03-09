package cangjiecoder

import std.collection.*
import std.convert.*
import std.env.*
import stdx.encoding.json.*

// MCP 工具上下文 —— 每次 tools/call 携带的运行时环境
struct McpToolContext {
    public McpToolContext(let workspaceRoot: String,
                          let serviceRoot: String,
                          let registry: SkillRegistry) {}
}

// MCP 工具处理函数类型：接收上下文和参数，返回工具结果 JSON
type McpToolHandler = (McpToolContext, JsonObject) -> String

// 将 LSP 查询结果包装为标准工具结果，提取 success 字段自动判定是否成功
func lspQueryToolResult(queryJson: String, okSummary: String, failSummary: String): String {
    let result = parseJsonObject(queryJson)
    let ok = jsonField(result, "success") == "true"
    return toolResultJson(ok, if (ok) { okSummary } else { failSummary }, data: result)
}

// 各 MCP 工具的独立处理函数

func handleSkillsSearch(ctx: McpToolContext, args: JsonObject): String {
    let query = jsonField(args, "query")
    let matches = ctx.registry.search(query, limit: 8)
    let data = parseJsonObject(skillsJson(matches))
    return toolResultJson(true, "Skills search completed", data: data)
}

func handleReadFile(ctx: McpToolContext, args: JsonObject): String {
    let path = jsonField(args, "path")
    let fullPath = ensureWorkspacePath(ctx.workspaceRoot, path)
    let content = readTextFile(fullPath)
    let data = JsonObject()
    data.put("path", JsonString(workspaceRelativePath(ctx.workspaceRoot, fullPath)))
    data.put("content", JsonString(content))
    data.put("bytes", JsonInt(content.toArray().size))
    return toolResultJson(true, "Read workspace file", data: data)
}

func handleListFiles(ctx: McpToolContext, args: JsonObject): String {
    return workspaceListFilesJson(ctx.workspaceRoot,
        jsonField(args, "path"),
        limit: parseJsonIntField(args, "limit", fallback: 200))
}

func handleSearchText(ctx: McpToolContext, args: JsonObject): String {
    return workspaceSearchTextJson(ctx.workspaceRoot,
        jsonField(args, "query"),
        jsonField(args, "path"),
        limit: parseJsonIntField(args, "limit", fallback: 20))
}

func handleReplaceText(ctx: McpToolContext, args: JsonObject): String {
    let message = replaceExactText(ctx.workspaceRoot,
        jsonField(args, "path"),
        jsonField(args, "oldText"),
        jsonField(args, "newText"))
    let ok = message.startsWith("updated ")
    return toolMessageJson(ok, if (ok) { "Updated workspace file text" } else { "Workspace text replacement rejected" }, message)
}

func handleCreateFile(ctx: McpToolContext, args: JsonObject): String {
    return workspaceCreateFileJson(ctx.workspaceRoot,
        jsonField(args, "path"),
        jsonField(args, "content"),
        overwrite: parseJsonBoolField(args, "overwrite", fallback: false))
}

func handleRunBuild(ctx: McpToolContext, args: JsonObject): String {
    return workspaceRunCommandJson(ctx.workspaceRoot, "cjpm", ["build"], jsonField(args, "path"))
}

func handleRunTest(ctx: McpToolContext, args: JsonObject): String {
    return workspaceRunCommandJson(ctx.workspaceRoot, "cjpm", ["test"], jsonField(args, "path"))
}

func handleRunCommand(ctx: McpToolContext, args: JsonObject): String {
    return workspaceRunCommandJson(ctx.workspaceRoot,
        jsonField(args, "command"),
        jsonStringArrayField(args, "args"),
        jsonField(args, "path"))
}

func handleAnalyzeFile(ctx: McpToolContext, args: JsonObject): String {
    let analysis = analyzeCangjieFile(ctx.workspaceRoot, jsonField(args, "path"))
    let data = parseJsonObject(analysisJson(analysis))
    return toolResultJson(analysis.success, analysis.summary, data: data)
}

func handleListExamples(ctx: McpToolContext, _: JsonObject): String {
    let data = parseJsonObject(exampleProjectsJson(ctx.serviceRoot))
    return toolResultJson(true, "Listed example projects", data: data)
}

func handleBootstrapJsonParser(ctx: McpToolContext, args: JsonObject): String {
    let message = bootstrapJsonParserProject(ctx.serviceRoot, ctx.workspaceRoot, jsonField(args, "path"))
    let ok = message.startsWith("Bootstrapped ")
    return toolMessageJson(ok, if (ok) { "Bootstrapped JsonParser example" } else { "JsonParser bootstrap did not complete" }, message)
}

func handleLspStatus(ctx: McpToolContext, _: JsonObject): String {
    let status = parseJsonObject(lspStatusJson(inspectLspStatus(ctx.workspaceRoot)))
    return toolResultJson(true, "Loaded Cangjie LSP status", data: status)
}

func handleLspProbe(ctx: McpToolContext, _: JsonObject): String {
    return lspQueryToolResult(lspProbeJson(probeLspServer(ctx.workspaceRoot)),
        "LSP probe succeeded", "LSP probe did not complete cleanly")
}

func handleLspDocumentSymbols(ctx: McpToolContext, args: JsonObject): String {
    return lspQueryToolResult(
        lspQueryJson(queryLspDocumentSymbols(ctx.workspaceRoot, jsonField(args, "path"))),
        "LSP document symbols loaded", "LSP document symbol query failed")
}

func handleLspWorkspaceSymbols(ctx: McpToolContext, args: JsonObject): String {
    return lspQueryToolResult(
        lspQueryJson(queryLspWorkspaceSymbols(ctx.workspaceRoot, jsonField(args, "query"))),
        "LSP workspace symbols loaded", "LSP workspace symbol query failed")
}

func handleLspDefinition(ctx: McpToolContext, args: JsonObject): String {
    return lspQueryToolResult(
        lspQueryJson(queryLspDefinition(ctx.workspaceRoot,
            jsonField(args, "path"),
            parseJsonIntField(args, "line", fallback: 0),
            parseJsonIntField(args, "column", fallback: 0))),
        "LSP definition loaded", "LSP definition query failed")
}

func handleEditAstNode(ctx: McpToolContext, args: JsonObject): String {
    // AST 编辑前尝试备份原始文件，支持事务回滚
    try {
        let fullPath = ensureWorkspacePath(ctx.workspaceRoot, jsonField(args, "path"))
        globalBackupStore.backup(fullPath)
    } catch (e: Exception) {
        // 路径无效时跳过备份，让 editAstNode 处理错误
    }
    let message = editAstNode(ctx.workspaceRoot,
        jsonField(args, "path"),
        jsonField(args, "nodeType"),
        jsonField(args, "replacement"),
        index: parseJsonIntField(args, "index", fallback: 0))
    let ok = astEditSucceeded(message)
    return toolMessageJson(ok, if (ok) { "AST node edit completed" } else { "AST node edit failed" }, message)
}

// 回滚所有被修改的文件到备份状态
func handleRollback(ctx: McpToolContext, _: JsonObject): String {
    if (!globalBackupStore.hasBackups()) {
        return toolMessageJson(true, "No file modifications to roll back", "No backups exist")
    }
    let restored = globalBackupStore.rollbackAll()
    let data = JsonObject()
    let restoredArray = JsonArray()
    for (path in restored) {
        restoredArray.add(JsonString(workspaceRelativePath(ctx.workspaceRoot, path)))
    }
    data.put("restoredFiles", restoredArray)
    data.put("count", JsonInt(restored.size))
    return toolResultJson(true, "Rolled back ${restored.size} file(s) to pre-edit state", data: data)
}

// 构建 MCP 工具名到处理函数的注册表
func buildMcpToolRegistry(): HashMap<String, McpToolHandler> {
    let registry = HashMap<String, McpToolHandler>()
    registry["skills.search"] = handleSkillsSearch
    registry["workspace.read_file"] = handleReadFile
    registry["workspace.list_files"] = handleListFiles
    registry["workspace.search_text"] = handleSearchText
    registry["workspace.replace_text"] = handleReplaceText
    registry["workspace.create_file"] = handleCreateFile
    registry["workspace.run_build"] = handleRunBuild
    registry["workspace.run_test"] = handleRunTest
    registry["workspace.run_command"] = handleRunCommand
    registry["cangjie.analyze_file"] = handleAnalyzeFile
    registry["project.list_examples"] = handleListExamples
    registry["project.bootstrap_json_parser"] = handleBootstrapJsonParser
    registry["cangjie.lsp_status"] = handleLspStatus
    registry["cangjie.lsp_probe"] = handleLspProbe
    registry["cangjie.lsp_document_symbols"] = handleLspDocumentSymbols
    registry["cangjie.lsp_workspace_symbols"] = handleLspWorkspaceSymbols
    registry["cangjie.lsp_definition"] = handleLspDefinition
    registry["cangjie.edit_ast_node"] = handleEditAstNode
    registry["workspace.rollback"] = handleRollback
    return registry
}

// MCP 工具调度 —— 在注册表中查找工具名并调用对应处理函数
func callMcpTool(toolRegistry: HashMap<String, McpToolHandler>,
                 ctx: McpToolContext,
                 toolName: String,
                 args: JsonObject): String {
    try {
        match (toolRegistry.get(toolName)) {
            case Some(handler) => return handler(ctx, args)
            case None => return toolMessageJson(false, "Unknown MCP tool", "Unknown tool: ${toolName}")
        }
    } catch (e: Exception) {
        return toolMessageJson(false, "MCP tool execution failed", shortPreview(e.toString(), maxLines: 12))
    }
}

// MCP JSON-RPC 方法处理函数类型：接收运行时、请求 ID JSON、params 参数，返回 JSON-RPC 响应字符串
type McpMethodHandler = (McpRuntime, String, JsonObject) -> String

// 各 MCP 协议方法的独立处理函数

func handleInitialize(_: McpRuntime, idJson: String, _: JsonObject): String {
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
}

func handlePing(_: McpRuntime, idJson: String, _: JsonObject): String {
    return jsonRpcResult(idJson, "{\"pong\":true}")
}

func handleNotificationsInitialized(_: McpRuntime, idJson: String, _: JsonObject): String {
    return jsonRpcResult(idJson, "null")
}

func handleToolsList(_: McpRuntime, idJson: String, _: JsonObject): String {
    return jsonRpcResult(idJson, toolDefinitionsJson())
}

func handleToolsCall(runtime: McpRuntime, idJson: String, params: JsonObject): String {
    let toolName = jsonField(params, "name")
    let toolArgs = match (params.get("arguments")) {
        case Some(value) => value.asObject()
        case None => JsonObject()
    }
    let ctx = McpToolContext(runtime.workspaceRoot, runtime.serviceRoot, runtime.registry)
    return jsonRpcResult(idJson, mcpToolCallResultJson(callMcpTool(runtime.toolRegistry, ctx, toolName, toolArgs)))
}

// 构建 MCP JSON-RPC 方法名到处理函数的注册表
func buildMcpMethodRegistry(): HashMap<String, McpMethodHandler> {
    let registry = HashMap<String, McpMethodHandler>()
    registry["initialize"] = handleInitialize
    registry["ping"] = handlePing
    registry["notifications/initialized"] = handleNotificationsInitialized
    registry["tools/list"] = handleToolsList
    registry["tools/call"] = handleToolsCall
    return registry
}

// McpRuntime 封装 MCP 协议的请求处理，被 stdio 和 HTTP 入口共用
class McpRuntime {
    public let workspaceRoot: String
    public let serviceRoot: String
    public let registry: SkillRegistry
    let methodRegistry: HashMap<String, McpMethodHandler>
    let toolRegistry: HashMap<String, McpToolHandler>

    public init(workspaceRoot: String, serviceRoot!: String = "") {
        this.workspaceRoot = workspaceRoot
        this.serviceRoot = if (serviceRoot.trimAscii().isEmpty()) { workspaceRoot } else { serviceRoot }
        this.registry = SkillRegistry(this.serviceRoot)
        this.methodRegistry = buildMcpMethodRegistry()
        this.toolRegistry = buildMcpToolRegistry()
    }

    // 处理单条 MCP JSON-RPC 请求，返回 None 表示通知类消息无需回复
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

            match (methodRegistry.get(method)) {
                case Some(handler) => return Some(handler(this, idJson, params))
                case None => return Some(jsonRpcError(idJson, -32601, "Unsupported MCP method: ${method}"))
            }
        } catch (e: Exception) {
            return Some(jsonRpcError("null", -32700, "Failed to parse MCP request: ${shortPreview(e.toString(), maxLines: 4)}"))
        }
    }
}

// MCP stdio 帧格式常量
const MCP_HEADER_DELIMITER: String = "\r\n\r\n"
const MCP_CONTENT_LENGTH_HEADER: String = "Content-Length:"
const STDIO_CHUNK_SIZE: Int64 = 4096

// 将 JSON 消息体编码为 MCP Content-Length 帧
func encodeMcpFrame(body: String): String {
    return "${MCP_CONTENT_LENGTH_HEADER} ${body.toArray().size}${MCP_HEADER_DELIMITER}${body}"
}

// 从标准输入逐字节读取一个 MCP 帧（Content-Length + body）
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

// 启动 MCP stdio 服务，循环读取帧并回写响应
func startMcpStdioServer(config: AppConfig): Unit {
    let runtime = McpRuntime(config.workspaceRoot, serviceRoot: config.serviceRoot)
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
