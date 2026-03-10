// MCP 协议层：工具定义、参数规格、JSON 序列化、帧编解码
package cangjiecoder.mcp

import std.convert.*
import std.env.*
import stdx.encoding.json.*

// MCP stdio 帧格式常量
public const MCP_HEADER_DELIMITER: String = "\r\n\r\n"
public const MCP_CONTENT_LENGTH_HEADER: String = "Content-Length:"
public const STDIO_CHUNK_SIZE: Int64 = 4096

public struct ToolArgSpec {
    public ToolArgSpec(public let name: String,
                       public let kind: String,
                       public let description: String,
                       public let required: Bool) {}
}

public struct ToolDefinition {
    public ToolDefinition(public let name: String,
                          public let description: String,
                          public let args: Array<ToolArgSpec>) {}
}

public func buildToolDefinitions(): Array<ToolDefinition> {
    return [
        ToolDefinition("skills.search", "Search built-in Cangjie skills stored in .github/skills.", [
            ToolArgSpec("query", "string", "Search keywords for skills lookup.", true)
        ]),
        ToolDefinition("workspace.read_file", "Read a file inside the repository root.", [
            ToolArgSpec("path", "string", "Repository-relative or absolute in-repo path.", true)
        ]),
        ToolDefinition("workspace.list_files", "Recursively list files inside the repository root or a subdirectory.", [
            ToolArgSpec("path", "string", "Optional repository-relative directory to list from. Defaults to the workspace root.", false),
            ToolArgSpec("limit", "integer", "Maximum number of files to return. Defaults to 200.", false)
        ]),
        ToolDefinition("workspace.search_text", "Search for exact text matches inside workspace files.", [
            ToolArgSpec("query", "string", "Exact text query to search for.", true),
            ToolArgSpec("path", "string", "Optional repository-relative directory to search in. Defaults to the workspace root.", false),
            ToolArgSpec("limit", "integer", "Maximum number of matches to return. Defaults to 20.", false)
        ]),
        ToolDefinition("workspace.replace_text", "Replace exactly one matched text block inside an existing file.", [
            ToolArgSpec("path", "string", "Repository-relative or absolute in-repo path.", true),
            ToolArgSpec("oldText", "string", "Exact text to replace.", true),
            ToolArgSpec("newText", "string", "Replacement text.", true)
        ]),
        ToolDefinition("workspace.create_file", "Create a new file inside the repository root and create missing parent directories when needed.", [
            ToolArgSpec("path", "string", "Repository-relative or absolute in-repo path.", true),
            ToolArgSpec("content", "string", "Initial file content. Defaults to an empty file when omitted.", false),
            ToolArgSpec("overwrite", "boolean", "When true, allow overwriting an existing file. Defaults to false.", false)
        ]),
        ToolDefinition("workspace.run_build", "Run cjpm build inside the workspace or a subdirectory.", [
            ToolArgSpec("path", "string", "Optional repository-relative working directory. Defaults to the workspace root.", false)
        ]),
        ToolDefinition("workspace.run_test", "Run cjpm test inside the workspace or a subdirectory.", [
            ToolArgSpec("path", "string", "Optional repository-relative working directory. Defaults to the workspace root.", false)
        ]),
        ToolDefinition("workspace.run_command", "Run a workspace command from a restricted allowlist for agent automation.", [
            ToolArgSpec("command", "string", "Allowed command name such as cjpm, cjc, cjlint, tree-sitter, grep, or find.", true),
            ToolArgSpec("args", "array", "Optional positional arguments for the allowed command.", false),
            ToolArgSpec("path", "string", "Optional repository-relative working directory. Defaults to the workspace root.", false)
        ]),
        ToolDefinition("cangjie.analyze_file", "Run tree-sitter/cjlint/cjc based analysis for a Cangjie source file.", [
            ToolArgSpec("path", "string", "Cangjie source file path.", true)
        ]),
        ToolDefinition("project.list_examples", "List built-in Cangjie example projects that can be bootstrapped into the workspace.", []),
        ToolDefinition("project.bootstrap_json_parser", "Copy the built-in JsonParser example project into a target workspace path.", [
            ToolArgSpec("path", "string", "Destination directory to create inside the workspace.", true)
        ]),
        ToolDefinition("cangjie.lsp_status", "Inspect whether a Cangjie LSP binary is configured or discoverable.", []),
        ToolDefinition("cangjie.lsp_probe", "Run a lightweight initialize/shutdown probe against the configured Cangjie LSP server.", []),
        ToolDefinition("cangjie.lsp_document_symbols", "Query the configured Cangjie LSP server for document symbols in a source file.", [
            ToolArgSpec("path", "string", "Cangjie source file path.", true)
        ]),
        ToolDefinition("cangjie.lsp_workspace_symbols", "Query the configured Cangjie LSP server for workspace-level symbol matches.", [
            ToolArgSpec("query", "string", "Symbol name or fuzzy symbol query. Empty string requests a broad symbol scan.", false)
        ]),
        ToolDefinition("cangjie.lsp_definition", "Resolve a symbol definition via the configured Cangjie LSP server.", [
            ToolArgSpec("path", "string", "Cangjie source file path.", true),
            ToolArgSpec("line", "integer", "Zero-based source line.", true),
            ToolArgSpec("column", "integer", "Zero-based source column.", true)
        ]),
        ToolDefinition("cangjie.edit_ast_node", "Replace the selected AST node using tree-sitter parse ranges.", [
            ToolArgSpec("path", "string", "Cangjie source file path.", true),
            ToolArgSpec("nodeType", "string", "Tree-sitter node type to replace.", true),
            ToolArgSpec("replacement", "string", "Replacement source text.", true),
            ToolArgSpec("index", "integer", "Zero-based match index when multiple nodes match. Defaults to 0 if omitted.", false)
        ]),
        ToolDefinition("workspace.rollback", "Roll back all file modifications made since the last successful validation, restoring files to their pre-edit state.", []),
        ToolDefinition("cangjie.ast_parse", "Parse Cangjie source code via built-in tree-sitter and return the S-expression syntax tree.", [
            ToolArgSpec("path", "string", "Cangjie source file path.", true)
        ]),
        ToolDefinition("cangjie.ast_query_nodes", "Query all AST nodes matching a given node type from a Cangjie source file.", [
            ToolArgSpec("path", "string", "Cangjie source file path.", true),
            ToolArgSpec("nodeType", "string", "Tree-sitter node type to search for (e.g. functionDefinition, classDefinition).", true)
        ]),
        ToolDefinition("cangjie.ast_list_nodes", "List all named AST nodes in a Cangjie source file up to a specified depth.", [
            ToolArgSpec("path", "string", "Cangjie source file path.", true),
            ToolArgSpec("maxDepth", "integer", "Maximum tree depth to traverse. Defaults to 4.", false)
        ])
    ]
}

public func toolDefinitionsJson(): String {
    let tools = JsonArray()
    for (tool in buildToolDefinitions()) {
        let item = JsonObject()
        item.put("name", JsonString(tool.name))
        item.put("description", JsonString(tool.description))

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

// JSON-RPC 2.0 成功响应
public func jsonRpcResult(idJson: String, resultJson: String): String {
    return "{\"jsonrpc\":\"2.0\",\"id\":${idJson},\"result\":${resultJson}}"
}

// JSON-RPC 2.0 错误响应
public func jsonRpcError(idJson: String, code: Int64, message: String): String {
    let error = JsonObject()
    error.put("code", JsonInt(code))
    error.put("message", JsonString(message))
    return "{\"jsonrpc\":\"2.0\",\"id\":${idJson},\"error\":${error.toString()}}"
}

// 将工具调用结果包装为 MCP content blocks 格式
public func mcpToolCallResultJson(content: String): String {
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
