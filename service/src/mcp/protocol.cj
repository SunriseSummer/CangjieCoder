// MCP 协议层：工具定义、参数规格、JSON 序列化、帧编解码
// 定义 26 个 MCP 工具的元数据（名称、描述、参数规格），
// 以及 JSON-RPC 2.0 响应构造和 MCP stdio 帧编解码能力。
package cangjiecoder.mcp

import std.collection.*
import std.convert.*
import std.env.*
import stdx.encoding.json.*

// ── MCP 协议常量 ─────────────────────────────────────

// MCP stdio 帧格式：头部以 \r\n\r\n 分隔，body 通过 Content-Length 指定长度
public const MCP_HEADER_DELIMITER: String = "\r\n\r\n"
public const MCP_CONTENT_LENGTH_HEADER: String = "Content-Length:"
// stdio body 分块读取大小
public const STDIO_CHUNK_SIZE: Int64 = 4096

// ── 工具定义数据类型 ─────────────────────────────────

// 工具参数规格：定义单个参数的名称、类型、描述和是否必填
public struct ToolArgSpec {
    public ToolArgSpec(public let name: String,
                       public let kind: String,
                       public let description: String,
                       public let required: Bool) {}
}

// 工具定义：定义单个工具的名称、功能描述和参数列表
public struct ToolDefinition {
    public ToolDefinition(public let name: String,
                          public let description: String,
                          public let args: Array<ToolArgSpec>) {}
}

// ── 工具注册表构建 ───────────────────────────────────

// 构建全部 24 个 MCP 工具的元数据定义，分为以下类别：
// - 技能检索（skills）
// - 工作区操作（workspace）
// - 仓颉分析与 AST（cangjie）
// - LSP 查询（cangjie.lsp_*）
// - 事务回滚（workspace.rollback）
public func buildToolDefinitions(): Array<ToolDefinition> {
    let defs = ArrayList<ToolDefinition>()
    // 技能检索
    defs.add(ToolDefinition("skills.search", "Search built-in Cangjie skills stored in .github/skills.", [
        ToolArgSpec("query", "string", "Search keywords for skills lookup.", true)
    ]))
    // 文件读写
    defs.add(ToolDefinition("workspace.read_file", "Read a file inside the repository root.", [
        ToolArgSpec("path", "string", "Repository-relative or absolute in-repo path.", true)
    ]))
    defs.add(ToolDefinition("workspace.list_files", "Recursively list files inside the repository root or a subdirectory.", [
        ToolArgSpec("path", "string", "Optional repository-relative directory to list from. Defaults to the workspace root.", false),
        ToolArgSpec("limit", "integer", "Maximum number of files to return. Defaults to 200.", false)
    ]))
    defs.add(ToolDefinition("workspace.search_text", "Search for exact text matches inside workspace files.", [
        ToolArgSpec("query", "string", "Exact text query to search for.", true),
        ToolArgSpec("path", "string", "Optional repository-relative directory to search in. Defaults to the workspace root.", false),
        ToolArgSpec("limit", "integer", "Maximum number of matches to return. Defaults to 20.", false)
    ]))
    defs.add(ToolDefinition("workspace.replace_text", "Replace exactly one matched text block inside an existing file.", [
        ToolArgSpec("path", "string", "Repository-relative or absolute in-repo path.", true),
        ToolArgSpec("oldText", "string", "Exact text to replace.", true),
        ToolArgSpec("newText", "string", "Replacement text.", true)
    ]))
    defs.add(ToolDefinition("workspace.create_file", "Create a new file inside the repository root and create missing parent directories when needed.", [
        ToolArgSpec("path", "string", "Repository-relative or absolute in-repo path.", true),
        ToolArgSpec("content", "string", "Initial file content. Defaults to an empty file when omitted.", false),
        ToolArgSpec("overwrite", "boolean", "When true, allow overwriting an existing file. Defaults to false.", false)
    ]))
    // 构建与测试
    defs.add(ToolDefinition("workspace.run_build", "Run cjpm build inside the workspace or a subdirectory.", [
        ToolArgSpec("path", "string", "Optional repository-relative working directory. Defaults to the workspace root.", false)
    ]))
    defs.add(ToolDefinition("workspace.run_test", "Run cjpm test inside the workspace or a subdirectory.", [
        ToolArgSpec("path", "string", "Optional repository-relative working directory. Defaults to the workspace root.", false)
    ]))
    defs.add(ToolDefinition("workspace.run_command", "Run a workspace command from a restricted allowlist for agent automation.", [
        ToolArgSpec("command", "string", "Allowed command name such as cjpm, cjc, cjlint, tree-sitter, grep, or find.", true),
        ToolArgSpec("args", "array", "Optional positional arguments for the allowed command.", false),
        ToolArgSpec("path", "string", "Optional repository-relative working directory. Defaults to the workspace root.", false)
    ]))
    // 仓颉分析
    defs.add(ToolDefinition("cangjie.analyze_file", "Run tree-sitter/cjlint/cjc based analysis for a Cangjie source file.", [
        ToolArgSpec("path", "string", "Cangjie source file path.", true)
    ]))
    // LSP 查询
    defs.add(ToolDefinition("cangjie.lsp_status", "Inspect whether a Cangjie LSP binary is configured or discoverable.", []))
    defs.add(ToolDefinition("cangjie.lsp_probe", "Run a lightweight initialize/shutdown probe against the configured Cangjie LSP server.", []))
    defs.add(ToolDefinition("cangjie.lsp_document_symbols", "Query the configured Cangjie LSP server for document symbols in a source file.", [
        ToolArgSpec("path", "string", "Cangjie source file path.", true)
    ]))
    defs.add(ToolDefinition("cangjie.lsp_workspace_symbols", "Query the configured Cangjie LSP server for workspace-level symbol matches.", [
        ToolArgSpec("query", "string", "Symbol name or fuzzy symbol query. Empty string requests a broad symbol scan.", false)
    ]))
    defs.add(ToolDefinition("cangjie.lsp_definition", "Resolve a symbol definition via the configured Cangjie LSP server.", [
        ToolArgSpec("path", "string", "Cangjie source file path.", true),
        ToolArgSpec("line", "integer", "Zero-based source line.", true),
        ToolArgSpec("column", "integer", "Zero-based source column.", true)
    ]))
    // AST 操作
    defs.add(ToolDefinition("cangjie.edit_ast_node", "Replace the selected AST node using tree-sitter parse ranges.", [
        ToolArgSpec("path", "string", "Cangjie source file path.", true),
        ToolArgSpec("nodeType", "string", "Tree-sitter node type to replace.", true),
        ToolArgSpec("replacement", "string", "Replacement source text.", true),
        ToolArgSpec("index", "integer", "Zero-based match index when multiple nodes match. Defaults to 0 if omitted.", false)
    ]))
    // 事务回滚
    defs.add(ToolDefinition("workspace.rollback", "Roll back all file modifications made since the last successful validation, restoring files to their pre-edit state.", []))
    // 工作区根目录管理
    defs.add(ToolDefinition("workspace.set_root", "Dynamically set the workspace root directory for this session. Use this when the MCP service was started without --repo or when switching to a different project mid-session. All subsequent tool calls will use the new workspace root unless overridden by a workspacePath argument.", [
        ToolArgSpec("path", "string", "Absolute path to the new workspace root directory.", true)
    ]))
    defs.add(ToolDefinition("workspace.get_root", "Return the current workspace root directory path. Useful for confirming which project directory the service is operating on.", []))
    // 内置 AST 服务
    defs.add(ToolDefinition("cangjie.ast_parse", "Parse Cangjie source code via built-in tree-sitter and return the S-expression syntax tree.", [
        ToolArgSpec("path", "string", "Cangjie source file path.", true)
    ]))
    defs.add(ToolDefinition("cangjie.ast_query_nodes", "Query all AST nodes matching a given node type from a Cangjie source file.", [
        ToolArgSpec("path", "string", "Cangjie source file path.", true),
        ToolArgSpec("nodeType", "string", "Tree-sitter node type to search for (e.g. functionDefinition, classDefinition).", true)
    ]))
    defs.add(ToolDefinition("cangjie.ast_list_nodes", "List all named AST nodes in a Cangjie source file up to a specified depth.", [
        ToolArgSpec("path", "string", "Cangjie source file path.", true),
        ToolArgSpec("maxDepth", "integer", "Maximum tree depth to traverse. Defaults to 4.", false)
    ]))
    defs.add(ToolDefinition("cangjie.ast_summary", "Generate a concise structural summary of a Cangjie source file listing top-level definitions (functions, classes, interfaces, structs, enums) with their signatures and line ranges. Ideal for quickly understanding file structure without reading the full source, significantly reducing Token consumption.", [
        ToolArgSpec("path", "string", "Cangjie source file path.", true)
    ]))
    defs.add(ToolDefinition("cangjie.ast_query_nodes_with_text", "Query AST nodes by type and return each node with its corresponding source text. Use this to inspect specific code elements (function bodies, class definitions) without reading the entire file.", [
        ToolArgSpec("path", "string", "Cangjie source file path.", true),
        ToolArgSpec("nodeType", "string", "Tree-sitter node type to search for (e.g. functionDefinition, classDefinition).", true)
    ]))
    // 批量技能检索
    defs.add(ToolDefinition("skills.batch_search", "Search multiple skill queries in a single request, returning results for each query. Reduces network round-trips and Token consumption when multiple skills are needed.", [
        ToolArgSpec("queries", "array", "Array of search query strings.", true)
    ]))
    defs.add(ToolDefinition("skills.prompt_context", "Generate a ready-to-use prompt context block from matching skills. Returns compact text that AI can embed directly in system prompts.", [
        ToolArgSpec("query", "string", "Search keywords for skills lookup.", true),
        ToolArgSpec("limit", "integer", "Maximum number of skills to include. Defaults to 3.", false)
    ]))
    return defs.toArray()
}

// ── 工具定义 JSON 序列化 ─────────────────────────────

// 将全部工具定义序列化为符合 MCP 协议的 JSON 格式（含 OpenAPI inputSchema）
public func toolDefinitionsJson(): String {
    let tools = JsonArray()
    for (tool in buildToolDefinitions()) {
        let item = JsonObject()
        item.put("name", JsonString(tool.name))
        item.put("description", JsonString(tool.description))

        // 构建 OpenAPI 风格的 inputSchema
        let schema = JsonObject()
        schema.put("type", JsonString("object"))
        let properties = JsonObject()
        let required = JsonArray()
        for (arg in tool.args) {
            let property = JsonObject()
            property.put("type", JsonString(arg.kind))
            property.put("description", JsonString(arg.description))
            properties.put(arg.name, property)
            if (arg.required) {
                required.add(JsonString(arg.name))
            }
        }
        schema.put("properties", properties)
        schema.put("required", required)
        item.put("inputSchema", schema)
        tools.add(item)
    }
    let root = JsonObject()
    root.put("tools", tools)
    return root.toString()
}

// ── JSON-RPC 2.0 响应构造 ────────────────────────────

// 构造 JSON-RPC 2.0 成功响应
public func jsonRpcResult(idJson: String, resultJson: String): String {
    return "{\"jsonrpc\":\"2.0\",\"id\":${idJson},\"result\":${resultJson}}"
}

// 构造 JSON-RPC 2.0 错误响应（含错误码和消息）
public func jsonRpcError(idJson: String, code: Int64, message: String): String {
    let error = JsonObject()
    error.put("code", JsonInt(code))
    error.put("message", JsonString(message))
    return "{\"jsonrpc\":\"2.0\",\"id\":${idJson},\"error\":${error.toString()}}"
}

// ── MCP 工具结果封装 ─────────────────────────────────

// 将工具调用结果包装为 MCP content blocks 格式，
// 根据 ok 字段判断 isError 状态
public func mcpToolCallResultJson(content: String): String {
    let toolResult = JsonValue.fromStr(content).asObject()

    // 构建文本内容块
    let textBlocks = JsonArray()
    let textBlock = JsonObject()
    textBlock.put("type", JsonString("text"))
    textBlock.put("text", JsonString(content))
    textBlocks.add(textBlock)

    // 判断工具执行是否出错
    let isError = match (toolResult.get("ok")) {
        case Some(value) => value.toString() != "true"
        case None => false
    }

    let result = JsonObject()
    result.put("content", textBlocks)
    result.put("structuredContent", toolResult)
    result.put("isError", JsonBool(isError))
    return result.toString()
}

// ── MCP 帧编解码 ─────────────────────────────────────

// 将 JSON 消息体编码为 MCP Content-Length 帧
public func encodeMcpFrame(body: String): String {
    return "${MCP_CONTENT_LENGTH_HEADER} ${body.toArray().size}${MCP_HEADER_DELIMITER}${body}"
}

// 从标准输入逐行/逐块读取一个 MCP 帧（Content-Length 头 + body）。
// 返回 None 表示输入流结束或帧格式无效。
public func readStdioFrame(reader: ConsoleReader): ?String {
    // 第一阶段：逐行读取头部，寻找 Content-Length 和空行分隔
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
                    } catch (_: Exception) {
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

    // 第二阶段：按 Content-Length 分块读取 body 字节
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
