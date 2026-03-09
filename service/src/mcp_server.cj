package cangjiecoder

import std.convert.*
import std.env.*
import stdx.encoding.json.*

// MCP 工具调度 —— 根据工具名分发到对应的工作区/LSP/AST 处理函数
func callMcpTool(workspaceRoot: String,
                 serviceRoot: String,
                 registry: SkillRegistry,
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
                let fullPath = ensureWorkspacePath(workspaceRoot, path)
                let content = readTextFile(fullPath)
                let data = JsonObject()
                data.put("path", JsonString(workspaceRelativePath(workspaceRoot, fullPath)))
                data.put("content", JsonString(content))
                data.put("bytes", JsonInt(content.toArray().size))
                return toolResultJson(true, "Read workspace file", data: data)
            case "workspace.list_files" =>
                return workspaceListFilesJson(workspaceRoot,
                    jsonField(args, "path"),
                    limit: parseJsonIntField(args, "limit", fallback: 200))
            case "workspace.search_text" =>
                return workspaceSearchTextJson(workspaceRoot,
                    jsonField(args, "query"),
                    jsonField(args, "path"),
                    limit: parseJsonIntField(args, "limit", fallback: 20))
            case "workspace.replace_text" =>
                let path = jsonField(args, "path")
                let oldText = jsonField(args, "oldText")
                let newText = jsonField(args, "newText")
                let message = replaceExactText(workspaceRoot, path, oldText, newText)
                let ok = message.startsWith("updated ")
                return toolMessageJson(ok, if (ok) { "Updated workspace file text" } else { "Workspace text replacement rejected" }, message)
            case "workspace.create_file" =>
                return workspaceCreateFileJson(workspaceRoot,
                    jsonField(args, "path"),
                    jsonField(args, "content"),
                    overwrite: parseJsonBoolField(args, "overwrite", fallback: false))
            case "workspace.run_build" =>
                return workspaceRunCommandJson(workspaceRoot, "cjpm", ["build"], jsonField(args, "path"))
            case "workspace.run_test" =>
                return workspaceRunCommandJson(workspaceRoot, "cjpm", ["test"], jsonField(args, "path"))
            case "workspace.run_command" =>
                return workspaceRunCommandJson(workspaceRoot,
                    jsonField(args, "command"),
                    jsonStringArrayField(args, "args"),
                    jsonField(args, "path"))
            case "cangjie.analyze_file" =>
                let path = jsonField(args, "path")
                let analysis = analyzeCangjieFile(workspaceRoot, path)
                let data = parseJsonObject(analysisJson(analysis))
                return toolResultJson(analysis.success, analysis.summary, data: data)
            case "project.list_examples" =>
                let data = parseJsonObject(exampleProjectsJson(serviceRoot))
                return toolResultJson(true, "Listed example projects", data: data)
            case "project.bootstrap_json_parser" =>
                let path = jsonField(args, "path")
                let message = bootstrapJsonParserProject(serviceRoot, workspaceRoot, path)
                let ok = message.startsWith("Bootstrapped ")
                return toolMessageJson(ok, if (ok) { "Bootstrapped JsonParser example" } else { "JsonParser bootstrap did not complete" }, message)
            case "cangjie.lsp_status" =>
                let status = parseJsonObject(lspStatusJson(inspectLspStatus(workspaceRoot)))
                return toolResultJson(true, "Loaded Cangjie LSP status", data: status)
            case "cangjie.lsp_probe" =>
                let result = parseJsonObject(lspProbeJson(probeLspServer(workspaceRoot)))
                let ok = jsonField(result, "success") == "true"
                return toolResultJson(ok, if (ok) { "LSP probe succeeded" } else { "LSP probe did not complete cleanly" }, data: result)
            case "cangjie.lsp_document_symbols" =>
                let result = parseJsonObject(lspQueryJson(queryLspDocumentSymbols(workspaceRoot, jsonField(args, "path"))))
                let ok = jsonField(result, "success") == "true"
                return toolResultJson(ok, if (ok) { "LSP document symbols loaded" } else { "LSP document symbol query failed" }, data: result)
            case "cangjie.lsp_workspace_symbols" =>
                let result = parseJsonObject(lspQueryJson(queryLspWorkspaceSymbols(workspaceRoot, jsonField(args, "query"))))
                let ok = jsonField(result, "success") == "true"
                return toolResultJson(ok, if (ok) { "LSP workspace symbols loaded" } else { "LSP workspace symbol query failed" }, data: result)
            case "cangjie.lsp_definition" =>
                let result = parseJsonObject(lspQueryJson(queryLspDefinition(workspaceRoot,
                    jsonField(args, "path"),
                    parseJsonIntField(args, "line", fallback: 0),
                    parseJsonIntField(args, "column", fallback: 0))))
                let ok = jsonField(result, "success") == "true"
                return toolResultJson(ok, if (ok) { "LSP definition loaded" } else { "LSP definition query failed" }, data: result)
            case "cangjie.edit_ast_node" =>
                let path = jsonField(args, "path")
                let nodeType = jsonField(args, "nodeType")
                let replacement = jsonField(args, "replacement")
                let index = parseJsonIntField(args, "index", fallback: 0)
                let message = editAstNode(workspaceRoot, path, nodeType, replacement, index: index)
                let ok = astEditSucceeded(message)
                return toolMessageJson(ok, if (ok) { "AST node edit completed" } else { "AST node edit failed" }, message)
            case _ =>
                return toolMessageJson(false, "Unknown MCP tool", "Unknown tool: ${toolName}")
        }
    } catch (e: Exception) {
        return toolMessageJson(false, "MCP tool execution failed", shortPreview(e.toString(), maxLines: 12))
    }
}

// McpRuntime 封装 MCP 协议的请求处理，被 stdio 和 HTTP 入口共用
class McpRuntime {
    let workspaceRoot: String
    let serviceRoot: String
    let registry: SkillRegistry

    public init(workspaceRoot: String, serviceRoot!: String = "") {
        this.workspaceRoot = workspaceRoot
        this.serviceRoot = if (serviceRoot.trimAscii().isEmpty()) { workspaceRoot } else { serviceRoot }
        this.registry = SkillRegistry(this.serviceRoot)
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
                    return Some(jsonRpcResult(idJson, mcpToolCallResultJson(callMcpTool(workspaceRoot,
                        serviceRoot,
                        registry,
                        toolName,
                        toolArgs))))
                case _ =>
                    return Some(jsonRpcError(idJson, -32601, "Unsupported MCP method: ${method}"))
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
