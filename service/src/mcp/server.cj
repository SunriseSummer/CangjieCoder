// MCP 工具处理：工具处理函数、工具/方法注册表、回调桥接
package cangjiecoder.mcp

import std.collection.*
import std.convert.*
import std.env.*
import std.fs.*
import stdx.encoding.json.*

// MCP 版本号（与根包 APP_VERSION 保持一致）
public const MCP_APP_VERSION: String = "0.3.0"

// MCP stdio 帧格式常量
public const MCP_HEADER_DELIMITER: String = "\r\n\r\n"
public const MCP_CONTENT_LENGTH_HEADER: String = "Content-Length:"
public const STDIO_CHUNK_SIZE: Int64 = 4096

// ---- 子包内部工具函数，避免对根包的循环依赖 ----

public func mcpJsonField(obj: JsonObject, key: String, fallback!: String = ""): String {
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

public func mcpParseJsonObject(body: String): JsonObject {
    if (body.trimAscii().isEmpty()) {
        return JsonObject()
    }
    return JsonValue.fromStr(body).asObject()
}

func mcpParseJsonIntField(obj: JsonObject, key: String, fallback!: Int64 = 0): Int64 {
    let raw = mcpJsonField(obj, key)
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

func mcpParseJsonBoolField(obj: JsonObject, key: String, fallback!: Bool = false): Bool {
    let raw = mcpJsonField(obj, key).trimAscii().toAsciiLower()
    if (raw.isEmpty()) {
        return fallback
    }
    if (raw == "true") {
        return true
    }
    if (raw == "false") {
        return false
    }
    return fallback
}

func mcpJsonStringArrayField(obj: JsonObject, key: String): Array<String> {
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

func mcpToolResultJson(ok: Bool, summary: String, data!: JsonValue = JsonObject()): String {
    let root = JsonObject()
    root.put("ok", JsonBool(ok))
    root.put("summary", JsonString(summary))
    root.put("data", data)
    return root.toString()
}

func mcpToolMessageJson(ok: Bool, summary: String, message: String): String {
    let data = JsonObject()
    data.put("message", JsonString(message))
    return mcpToolResultJson(ok, summary, data: data)
}

func mcpShortPreview(text: String, maxLines!: Int64 = 8): String {
    let lines = ArrayList<String>()
    var count = 0
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

func mcpReadTextFile(path: String): String {
    return String.fromUtf8(File.readFrom(path))
}

func mcpWorkspaceRelativePath(repoRoot: String, path: String): String {
    let canonicalRoot = canonicalize(repoRoot).toString()
    let canonicalPath = if (exists(path)) {
        canonicalize(path).toString()
    } else {
        path
    }
    if (canonicalPath == canonicalRoot) {
        return "."
    }
    let prefix = "${canonicalRoot}/"
    if (canonicalPath.startsWith(prefix)) {
        return canonicalPath[prefix.size..canonicalPath.size]
    }
    return canonicalPath
}

func mcpEnsureWorkspacePath(repoRoot: String, path: String): String {
    let canonicalRoot = canonicalize(repoRoot).toString()
    let fullPath = if (path.startsWith("/")) { path } else { "${repoRoot}/${path}" }
    if (!exists(fullPath)) {
        throw IllegalArgumentException("Path does not exist: ${path}")
    }
    let canonicalPath = canonicalize(fullPath).toString()
    if (!canonicalPath.startsWith(canonicalRoot)) {
        throw IllegalArgumentException("Path escapes repository root: ${path}")
    }
    return canonicalPath
}

// ---- 工作区操作回调 ----
// McpWorkspaceOps 汇总所有根包域函数引用，由根包在创建 McpRuntime 时注入。
// 这种"函数引用桥接"方式让子包可以调用根包逻辑而不产生循环依赖。
public struct McpWorkspaceOps {
    public McpWorkspaceOps(
        public let replaceExactText: (String, String, String, String) -> String,
        public let workspaceListFilesJson: (String, String, Int64) -> String,
        public let workspaceSearchTextJson: (String, String, String, Int64) -> String,
        public let workspaceCreateFileJson: (String, String, String, Bool) -> String,
        public let workspaceRunCommandJson: (String, String, Array<String>, String) -> String,
        public let analyzeFileJson: (String, String) -> String,
        public let exampleProjectsJson: (String) -> String,
        public let bootstrapJsonParserProject: (String, String, String) -> String,
        public let skillsSearchJson: (String, String, Int64) -> String,
        public let editAstNodeJson: (String, String, String, String, Int64) -> String,
        public let lspStatusJson: (String) -> String,
        public let lspProbeJson: (String) -> String,
        public let lspDocumentSymbolsJson: (String, String) -> String,
        public let lspWorkspaceSymbolsJson: (String, String) -> String,
        public let lspDefinitionJson: (String, String, Int64, Int64) -> String,
        public let backupFile: (String) -> Unit,
        public let hasBackups: () -> Bool,
        public let rollbackAll: () -> Array<String>
    ) {}
}

// MCP 工具上下文 —— 每次 tools/call 携带的运行时环境
public struct McpToolContext {
    public McpToolContext(public let workspaceRoot: String,
                          public let serviceRoot: String,
                          public let ops: McpWorkspaceOps) {}
}

// MCP 工具处理函数类型
public type McpToolHandler = (McpToolContext, JsonObject) -> String

// 将 LSP 查询结果包装为标准工具结果
func lspQueryToolResult(queryJson: String, okSummary: String, failSummary: String): String {
    let result = mcpParseJsonObject(queryJson)
    let ok = mcpJsonField(result, "success") == "true"
    return mcpToolResultJson(ok, if (ok) { okSummary } else { failSummary }, data: result)
}

// ---- 各 MCP 工具的独立处理函数 ----

func handleSkillsSearch(ctx: McpToolContext, args: JsonObject): String {
    let query = mcpJsonField(args, "query")
    return ctx.ops.skillsSearchJson(ctx.serviceRoot, query, 8)
}

func handleReadFile(ctx: McpToolContext, args: JsonObject): String {
    let path = mcpJsonField(args, "path")
    let fullPath = mcpEnsureWorkspacePath(ctx.workspaceRoot, path)
    let content = mcpReadTextFile(fullPath)
    let data = JsonObject()
    data.put("path", JsonString(mcpWorkspaceRelativePath(ctx.workspaceRoot, fullPath)))
    data.put("content", JsonString(content))
    data.put("bytes", JsonInt(content.toArray().size))
    return mcpToolResultJson(true, "Read workspace file", data: data)
}

func handleListFiles(ctx: McpToolContext, args: JsonObject): String {
    return ctx.ops.workspaceListFilesJson(ctx.workspaceRoot,
        mcpJsonField(args, "path"),
        mcpParseJsonIntField(args, "limit", fallback: 200))
}

func handleSearchText(ctx: McpToolContext, args: JsonObject): String {
    return ctx.ops.workspaceSearchTextJson(ctx.workspaceRoot,
        mcpJsonField(args, "query"),
        mcpJsonField(args, "path"),
        mcpParseJsonIntField(args, "limit", fallback: 20))
}

func handleReplaceText(ctx: McpToolContext, args: JsonObject): String {
    let message = ctx.ops.replaceExactText(ctx.workspaceRoot,
        mcpJsonField(args, "path"),
        mcpJsonField(args, "oldText"),
        mcpJsonField(args, "newText"))
    let ok = message.startsWith("updated ")
    return mcpToolMessageJson(ok, if (ok) { "Updated workspace file text" } else { "Workspace text replacement rejected" }, message)
}

func handleCreateFile(ctx: McpToolContext, args: JsonObject): String {
    return ctx.ops.workspaceCreateFileJson(ctx.workspaceRoot,
        mcpJsonField(args, "path"),
        mcpJsonField(args, "content"),
        mcpParseJsonBoolField(args, "overwrite", fallback: false))
}

func handleRunBuild(ctx: McpToolContext, args: JsonObject): String {
    return ctx.ops.workspaceRunCommandJson(ctx.workspaceRoot, "cjpm", ["build"], mcpJsonField(args, "path"))
}

func handleRunTest(ctx: McpToolContext, args: JsonObject): String {
    return ctx.ops.workspaceRunCommandJson(ctx.workspaceRoot, "cjpm", ["test"], mcpJsonField(args, "path"))
}

func handleRunCommand(ctx: McpToolContext, args: JsonObject): String {
    return ctx.ops.workspaceRunCommandJson(ctx.workspaceRoot,
        mcpJsonField(args, "command"),
        mcpJsonStringArrayField(args, "args"),
        mcpJsonField(args, "path"))
}

func handleAnalyzeFile(ctx: McpToolContext, args: JsonObject): String {
    return ctx.ops.analyzeFileJson(ctx.workspaceRoot, mcpJsonField(args, "path"))
}

func handleListExamples(ctx: McpToolContext, _: JsonObject): String {
    let data = mcpParseJsonObject(ctx.ops.exampleProjectsJson(ctx.serviceRoot))
    return mcpToolResultJson(true, "Listed example projects", data: data)
}

func handleBootstrapJsonParser(ctx: McpToolContext, args: JsonObject): String {
    let message = ctx.ops.bootstrapJsonParserProject(ctx.serviceRoot, ctx.workspaceRoot, mcpJsonField(args, "path"))
    let ok = message.startsWith("Bootstrapped ")
    return mcpToolMessageJson(ok, if (ok) { "Bootstrapped JsonParser example" } else { "JsonParser bootstrap did not complete" }, message)
}

func handleLspStatus(ctx: McpToolContext, _: JsonObject): String {
    let status = mcpParseJsonObject(ctx.ops.lspStatusJson(ctx.workspaceRoot))
    return mcpToolResultJson(true, "Loaded Cangjie LSP status", data: status)
}

func handleLspProbe(ctx: McpToolContext, _: JsonObject): String {
    return lspQueryToolResult(ctx.ops.lspProbeJson(ctx.workspaceRoot),
        "LSP probe succeeded", "LSP probe did not complete cleanly")
}

func handleLspDocumentSymbols(ctx: McpToolContext, args: JsonObject): String {
    return lspQueryToolResult(
        ctx.ops.lspDocumentSymbolsJson(ctx.workspaceRoot, mcpJsonField(args, "path")),
        "LSP document symbols loaded", "LSP document symbol query failed")
}

func handleLspWorkspaceSymbols(ctx: McpToolContext, args: JsonObject): String {
    return lspQueryToolResult(
        ctx.ops.lspWorkspaceSymbolsJson(ctx.workspaceRoot, mcpJsonField(args, "query")),
        "LSP workspace symbols loaded", "LSP workspace symbol query failed")
}

func handleLspDefinition(ctx: McpToolContext, args: JsonObject): String {
    return lspQueryToolResult(
        ctx.ops.lspDefinitionJson(ctx.workspaceRoot,
            mcpJsonField(args, "path"),
            mcpParseJsonIntField(args, "line", fallback: 0),
            mcpParseJsonIntField(args, "column", fallback: 0)),
        "LSP definition loaded", "LSP definition query failed")
}

func handleEditAstNode(ctx: McpToolContext, args: JsonObject): String {
    // AST 编辑前尝试备份原始文件，支持事务回滚
    try {
        let fullPath = mcpEnsureWorkspacePath(ctx.workspaceRoot, mcpJsonField(args, "path"))
        ctx.ops.backupFile(fullPath)
    } catch (e: Exception) {
        // 路径无效时跳过备份，让 editAstNode 处理错误
    }
    let message = ctx.ops.editAstNodeJson(ctx.workspaceRoot,
        mcpJsonField(args, "path"),
        mcpJsonField(args, "nodeType"),
        mcpJsonField(args, "replacement"),
        mcpParseJsonIntField(args, "index", fallback: 0))
    let ok = !message.startsWith("tree-sitter unavailable") &&
        !message.contains("No AST node matched") &&
        !message.contains("Path does not exist") &&
        !message.contains("escapes repository root")
    return mcpToolMessageJson(ok, if (ok) { "AST node edit completed" } else { "AST node edit failed" }, message)
}

// 回滚所有被修改的文件到备份状态
func handleRollback(ctx: McpToolContext, _: JsonObject): String {
    if (!ctx.ops.hasBackups()) {
        return mcpToolMessageJson(true, "No file modifications to roll back", "No backups exist")
    }
    let restored = ctx.ops.rollbackAll()
    let data = JsonObject()
    let restoredArray = JsonArray()
    for (path in restored) {
        restoredArray.add(JsonString(mcpWorkspaceRelativePath(ctx.workspaceRoot, path)))
    }
    data.put("restoredFiles", restoredArray)
    data.put("count", JsonInt(restored.size))
    return mcpToolResultJson(true, "Rolled back ${restored.size} file(s) to pre-edit state", data: data)
}

// 构建 MCP 工具名到处理函数的注册表
public func buildMcpToolRegistry(): HashMap<String, McpToolHandler> {
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
public func callMcpTool(toolRegistry: HashMap<String, McpToolHandler>,
                 ctx: McpToolContext,
                 toolName: String,
                 args: JsonObject): String {
    try {
        match (toolRegistry.get(toolName)) {
            case Some(handler) => return handler(ctx, args)
            case None => return mcpToolMessageJson(false, "Unknown MCP tool", "Unknown tool: ${toolName}")
        }
    } catch (e: Exception) {
        return mcpToolMessageJson(false, "MCP tool execution failed", mcpShortPreview(e.toString(), maxLines: 12))
    }
}

// ---- MCP JSON-RPC 方法处理 ----

// MCP JSON-RPC 方法处理函数类型
public type McpMethodHandler = (McpRuntime, String, JsonObject) -> String

func handleInitialize(_: McpRuntime, idJson: String, _: JsonObject): String {
    let result = JsonObject()
    let capabilities = JsonObject()
    capabilities.put("tools", JsonObject())
    capabilities.put("prompts", JsonObject())
    capabilities.put("resources", JsonObject())
    result.put("capabilities", capabilities)
    let serverInfo = JsonObject()
    serverInfo.put("name", JsonString("CangjieCoder"))
    serverInfo.put("version", JsonString(MCP_APP_VERSION))
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
    let toolName = mcpJsonField(params, "name")
    let toolArgs = match (params.get("arguments")) {
        case Some(value) => value.asObject()
        case None => JsonObject()
    }
    let ctx = McpToolContext(runtime.workspaceRoot, runtime.serviceRoot, runtime.ops)
    return jsonRpcResult(idJson, mcpToolCallResultJson(callMcpTool(runtime.toolRegistry, ctx, toolName, toolArgs)))
}

// 构建 MCP JSON-RPC 方法名到处理函数的注册表
public func buildMcpMethodRegistry(): HashMap<String, McpMethodHandler> {
    let registry = HashMap<String, McpMethodHandler>()
    registry["initialize"] = handleInitialize
    registry["ping"] = handlePing
    registry["notifications/initialized"] = handleNotificationsInitialized
    registry["tools/list"] = handleToolsList
    registry["tools/call"] = handleToolsCall
    return registry
}

// ---- McpRuntime ----

// McpRuntime 封装 MCP 协议的请求处理，被 stdio 和 HTTP 入口共用
public class McpRuntime {
    public let workspaceRoot: String
    public let serviceRoot: String
    public let ops: McpWorkspaceOps
    let methodRegistry: HashMap<String, McpMethodHandler>
    public let toolRegistry: HashMap<String, McpToolHandler>

    public init(workspaceRoot: String, serviceRoot!: String = "", ops!: McpWorkspaceOps) {
        this.workspaceRoot = workspaceRoot
        this.serviceRoot = if (serviceRoot.trimAscii().isEmpty()) { workspaceRoot } else { serviceRoot }
        this.ops = ops
        this.methodRegistry = buildMcpMethodRegistry()
        this.toolRegistry = buildMcpToolRegistry()
    }

    // 处理单条 MCP JSON-RPC 请求，返回 None 表示通知类消息无需回复
    public func handleRequest(body: String): ?String {
        try {
            let request = mcpParseJsonObject(body)
            let (hasId, idJson) = match (request.get("id")) {
                case Some(value) => (true, value.toString())
                case None => (false, "null")
            }
            let method = mcpJsonField(request, "method")
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
            return Some(jsonRpcError("null", -32700, "Failed to parse MCP request: ${mcpShortPreview(e.toString(), maxLines: 4)}"))
        }
    }
}

// 将 JSON 消息体编码为 MCP Content-Length 帧
public func encodeMcpFrame(body: String): String {
    return "${MCP_CONTENT_LENGTH_HEADER} ${body.toArray().size}${MCP_HEADER_DELIMITER}${body}"
}

// 从标准输入逐字节读取一个 MCP 帧（Content-Length + body）
public func readStdioFrame(reader: ConsoleReader): ?String {
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
public func startMcpStdioServer(runtime: McpRuntime): Unit {
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
