package cangjiecoder

import std.collection.*
import std.convert.*
import std.fs.*
import stdx.encoding.json.*

// LSP 协议常量
const LSP_HEADER_DELIMITER: String = "\r\n\r\n"
const LSP_CONTENT_LENGTH_HEADER: String = "Content-Length:"
const JSON_NULL_LITERAL: String = "null"
const JSON_EMPTY_ARRAY_LITERAL: String = "[]"
const JSON_EMPTY_OBJECT_LITERAL: String = "{}"

// 持久化 LSP 会话相关常量
const LSP_MAX_INITIALIZE_ATTEMPTS: Int64 = 20
const LSP_MAX_QUERY_ATTEMPTS: Int64 = 50
const LSP_BODY_READ_BUFFER_SIZE: Int64 = 4096

struct LspStatus {
    public LspStatus(let available: Bool,
                     let command: String,
                     let summary: String,
                     let sourceHint: String) {}
}

struct LspProbeResult {
    public LspProbeResult(let available: Bool,
                          let success: Bool,
                          let command: String,
                          let summary: String,
                          let responsePreview: String) {}
}

struct LspQueryResult {
    public LspQueryResult(let available: Bool,
                          let success: Bool,
                          let command: String,
                          let method: String,
                          let summary: String,
                          let responsePreview: String,
                          let resultJson: String) {}
}

// 将 JSON 消息体编码为 LSP Content-Length 帧
func encodeLspFrame(body: String): String {
    return "${LSP_CONTENT_LENGTH_HEADER} ${body.toArray().size}${LSP_HEADER_DELIMITER}${body}"
}

func buildLspRequest(id: Int64, method: String, params: JsonValue): String {
    let root = JsonObject()
    root.put("jsonrpc", JsonString("2.0"))
    root.put("id", JsonInt(id))
    root.put("method", JsonString(method))
    root.put("params", params)
    return root.toString()
}

func buildLspNotification(method: String, params: JsonValue): String {
    let root = JsonObject()
    root.put("jsonrpc", JsonString("2.0"))
    root.put("method", JsonString(method))
    root.put("params", params)
    return root.toString()
}

// 从 LSP 多帧拼接的原始输出中解析出各个 JSON body
func extractLspBodies(raw: String): Array<String> {
    let bodies = ArrayList<String>()
    var offset: Int64 = 0
    while (offset < raw.size) {
        let headerEnd = match (raw.indexOf(LSP_HEADER_DELIMITER, offset)) {
            case Some(value) => value
            case None => break
        }
        let headers = raw[offset..headerEnd]
        let lengthStart = match (headers.indexOf(LSP_CONTENT_LENGTH_HEADER)) {
            case Some(value) => value + LSP_CONTENT_LENGTH_HEADER.size
            case None => break
        }
        let lengthLineEnd = match (headers.indexOf("\r\n", lengthStart)) {
            case Some(value) => value
            case None => headers.size
        }
        let length = Int64.parse(headers[lengthStart..lengthLineEnd].trimAscii())
        let bodyStart = headerEnd + LSP_HEADER_DELIMITER.size
        let bodyEnd = bodyStart + length
        if (bodyEnd > raw.size) {
            break
        }
        bodies.add(raw[bodyStart..bodyEnd])
        offset = bodyEnd
    }
    return bodies.toArray()
}

// 将文件系统路径转为 file:// URI，转义特殊字符
func fileUri(path: String): String {
    let canonicalPath = canonicalize(path).toString()
    let encodedPath = canonicalPath
        .replace("%", "%25")
        .replace(" ", "%20")
        .replace("#", "%23")
        .replace("?", "%3F")
    return "file://${encodedPath}"
}

func buildDidOpenNotification(path: String): String {
    let textDocument = JsonObject()
    textDocument.put("uri", JsonString(fileUri(path)))
    textDocument.put("languageId", JsonString("cangjie"))
    textDocument.put("version", JsonInt(1))
    textDocument.put("text", JsonString(readTextFile(path)))
    let params = JsonObject()
    params.put("textDocument", textDocument)
    return buildLspNotification("textDocument/didOpen", params)
}

func buildTextDocumentPositionParams(fullPath: String, line: Int64, column: Int64): JsonObject {
    let textDocument = JsonObject()
    textDocument.put("uri", JsonString(fileUri(fullPath)))
    let position = JsonObject()
    position.put("line", JsonInt(line))
    position.put("character", JsonInt(column))
    let params = JsonObject()
    params.put("textDocument", textDocument)
    params.put("position", position)
    return params
}

func lspResultToJsonValue(text: String): JsonValue {
    if (text.trimAscii().isEmpty()) {
        return JsonNull()
    }
    try {
        return JsonValue.fromStr(text)
    } catch (e: Exception) {
        return JsonString(text)
    }
}

// 构造 LSP initialize 请求的参数对象，含 clientInfo、rootUri、workspaceFolders 等
func buildLspInitializeParams(repoRoot!: ?String = None): JsonObject {
    let params = JsonObject()
    params.put("processId", JsonNull())
    let clientInfo = JsonObject()
    clientInfo.put("name", JsonString("CangjieCoder"))
    clientInfo.put("version", JsonString(APP_VERSION))
    params.put("clientInfo", clientInfo)

    match (repoRoot) {
        case Some(root) =>
            params.put("rootUri", JsonString(fileUri(root)))
            let workspaceFolder = JsonObject()
            workspaceFolder.put("uri", JsonString(fileUri(root)))
            workspaceFolder.put("name", JsonString(Path(root).fileName))
            let workspaceFolders = JsonArray()
            workspaceFolders.add(workspaceFolder)
            params.put("workspaceFolders", workspaceFolders)
        case None =>
            params.put("rootUri", JsonNull())
    }

    params.put("capabilities", JsonObject())
    return params
}

// 在响应体数组中查找指定 id 的 JSON-RPC 应答
func findLspResponseById(bodies: Array<String>, requestId: Int64): ?(String, JsonObject) {
    let idStr = "${requestId}"
    for (body in bodies) {
        try {
            let response = JsonValue.fromStr(body).asObject()
            let responseId = match (response.get("id")) {
                case Some(value) => value.toString()
                case None => ""
            }
            if (responseId == idStr) {
                return (body, response)
            }
        } catch (e: Exception) {
            continue
        }
    }
    return None
}

// 将 JSON-RPC 应答分类为 error/result，返回结构化的 LspQueryResult
func classifyLspResponse(command: String, method: String, body: String, response: JsonObject): LspQueryResult {
    if (let Some(errorValue) <- response.get("error")) {
        return LspQueryResult(true, false, command, method,
            "LSP request returned an error.",
            shortPreview(body, maxLines: 12),
            errorValue.toString())
    }
    if (let Some(resultValue) <- response.get("result")) {
        let resultText = resultValue.toString()
        let summary = if (resultText == JSON_NULL_LITERAL ||
            resultText == JSON_EMPTY_ARRAY_LITERAL ||
            resultText == JSON_EMPTY_OBJECT_LITERAL) {
            "LSP request succeeded, but the server returned no symbol payload."
        } else {
            "LSP request succeeded."
        }
        return LspQueryResult(true, true, command, method,
            summary, shortPreview(body, maxLines: 12), resultText)
    }
    return LspQueryResult(true, false, command, method,
        "LSP response contained neither result nor error.",
        shortPreview(body, maxLines: 12), JSON_NULL_LITERAL)
}
