// LSP 协议层：类型定义、常量、帧编解码、消息构建
package cangjiecoder.lsp

import std.collection.*
import std.convert.*
import std.fs.*
import stdx.encoding.json.*

// LSP 协议常量
public const LSP_HEADER_DELIMITER: String = "\r\n\r\n"
public const LSP_CONTENT_LENGTH_HEADER: String = "Content-Length:"
public const JSON_NULL_LITERAL: String = "null"
public const JSON_EMPTY_ARRAY_LITERAL: String = "[]"
public const JSON_EMPTY_OBJECT_LITERAL: String = "{}"

// 持久化 LSP 会话相关常量
public const LSP_MAX_INITIALIZE_ATTEMPTS: Int64 = 20
public const LSP_MAX_QUERY_ATTEMPTS: Int64 = 50
public const LSP_BODY_READ_BUFFER_SIZE: Int64 = 4096

// 与根包 APP_VERSION 保持一致的版本号
public const LSP_APP_VERSION: String = "0.3.0"

public struct LspStatus {
    public LspStatus(public let available: Bool,
                     public let command: String,
                     public let summary: String,
                     public let sourceHint: String) {}
}

public struct LspProbeResult {
    public LspProbeResult(public let available: Bool,
                          public let success: Bool,
                          public let command: String,
                          public let summary: String,
                          public let responsePreview: String) {}
}

public struct LspQueryResult {
    public LspQueryResult(public let available: Bool,
                          public let success: Bool,
                          public let command: String,
                          public let method: String,
                          public let summary: String,
                          public let responsePreview: String,
                          public let resultJson: String) {}
}

// 将 JSON 消息体编码为 LSP Content-Length 帧
public func encodeLspFrame(body: String): String {
    return "${LSP_CONTENT_LENGTH_HEADER} ${body.toArray().size}${LSP_HEADER_DELIMITER}${body}"
}

public func buildLspRequest(id: Int64, method: String, params: JsonValue): String {
    let root = JsonObject()
    root.put("jsonrpc", JsonString("2.0"))
    root.put("id", JsonInt(id))
    root.put("method", JsonString(method))
    root.put("params", params)
    return root.toString()
}

public func buildLspNotification(method: String, params: JsonValue): String {
    let root = JsonObject()
    root.put("jsonrpc", JsonString("2.0"))
    root.put("method", JsonString(method))
    root.put("params", params)
    return root.toString()
}

// 从 LSP 多帧拼接的原始输出中解析出各个 JSON body
public func extractLspBodies(raw: String): Array<String> {
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
public func fileUri(path: String): String {
    let canonicalPath = canonicalize(path).toString()
    let encodedPath = canonicalPath
        .replace("%", "%25")
        .replace(" ", "%20")
        .replace("#", "%23")
        .replace("?", "%3F")
    return "file://${encodedPath}"
}

// 在响应体数组中查找指定 id 的 JSON-RPC 应答
public func findLspResponseById(bodies: Array<String>, requestId: Int64): ?(String, JsonObject) {
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

public func lspResultToJsonValue(text: String): JsonValue {
    if (text.trimAscii().isEmpty()) {
        return JsonNull()
    }
    try {
        return JsonValue.fromStr(text)
    } catch (e: Exception) {
        return JsonString(text)
    }
}

// 子包内部使用的简易文本预览（截取前 N 行非空行）
public func lspShortPreview(text: String, maxLines!: Int64 = 8): String {
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

// 将 JSON-RPC 应答分类为 error/result，返回结构化的 LspQueryResult
public func classifyLspResponse(command: String, method: String, body: String, response: JsonObject): LspQueryResult {
    if (let Some(errorValue) <- response.get("error")) {
        return LspQueryResult(true, false, command, method,
            "LSP request returned an error.",
            lspShortPreview(body, maxLines: 12),
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
            summary, lspShortPreview(body, maxLines: 12), resultText)
    }
    return LspQueryResult(true, false, command, method,
        "LSP response contained neither result nor error.",
        lspShortPreview(body, maxLines: 12), JSON_NULL_LITERAL)
}
