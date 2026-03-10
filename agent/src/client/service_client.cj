// MCP 客户端：服务通信、stdio 帧编解码
package cangjiecoderagent.client

import std.collection.*
import std.convert.*
import std.fs.*
import std.process.*
import stdx.encoding.json.*
import cangjiecoderagent.common.*

public const MCP_HEADER_DELIMITER: String = "\r\n\r\n"
public const MCP_CONTENT_LENGTH_HEADER: String = "Content-Length:"

public func encodeMcpFrame(body: String): String {
    return "${MCP_CONTENT_LENGTH_HEADER} ${body.toArray().size}${MCP_HEADER_DELIMITER}${body}"
}

public func extractMcpBodies(raw: String): Array<String> {
    let bodies = ArrayList<String>()
    var offset: Int64 = 0
    while (offset < raw.size) {
        let headerEnd = match (raw.indexOf(MCP_HEADER_DELIMITER, offset)) {
            case Some(value) => value
            case None => break
        }
        let headers = raw[offset..headerEnd]
        let lengthStart = match (headers.indexOf(MCP_CONTENT_LENGTH_HEADER)) {
            case Some(value) => value + MCP_CONTENT_LENGTH_HEADER.size
            case None => break
        }
        let lengthLineEnd = match (headers.indexOf("\r\n", lengthStart)) {
            case Some(value) => value
            case None => headers.size
        }
        let length = Int64.parse(headers[lengthStart..lengthLineEnd].trimAscii())
        let bodyStart = headerEnd + MCP_HEADER_DELIMITER.size
        let bodyEnd = bodyStart + length
        if (bodyEnd > raw.size) {
            break
        }
        bodies.add(raw[bodyStart..bodyEnd])
        offset = bodyEnd
    }
    return bodies.toArray()
}

public func buildJsonRpcRequest(id: Int64, method: String, params: JsonValue): String {
    let root = JsonObject()
    root.put("jsonrpc", JsonString("2.0"))
    root.put("id", JsonInt(id))
    root.put("method", JsonString(method))
    root.put("params", params)
    return root.toString()
}

public func resolveServiceCommand(serviceDir: String, workspaceRoot: String): String {
    let releaseBinary = "${serviceDir}/target/release/bin/main"
    let debugBinary = "${serviceDir}/target/debug/bin/main"
    let command = if (exists(releaseBinary)) {
        clientShellQuote(releaseBinary)
    } else if (exists(debugBinary)) {
        clientShellQuote(debugBinary)
    } else {
        let runArgs = clientShellQuote("mcp-stdio --repo ${workspaceRoot}")
        return "cd ${clientShellQuote(serviceDir)} && printf '%s' __PAYLOAD__ | cjpm run --run-args ${runArgs}"
    }
    return "cd ${clientShellQuote(serviceDir)} && printf '%s' __PAYLOAD__ | ${command} mcp-stdio --repo ${clientShellQuote(workspaceRoot)}"
}

public class ServiceClient {
    let config: AgentConfig

    public init(config: AgentConfig) {
        this.config = config
    }

    public func listToolsJson(): String {
        let response = invokeMcp(buildJsonRpcRequest(2, "tools/list", JsonObject()))
        return clientJsonField(response, "result")
    }

    public func callTool(name: String, arguments: JsonObject): JsonObject {
        let params = JsonObject()
        params.put("name", JsonString(name))
        params.put("arguments", arguments)
        let response = invokeMcp(buildJsonRpcRequest(2, "tools/call", params))
        let result = clientParseJsonObject(clientJsonField(response, "result", fallback: "{}"))
        return clientParseJsonObject(clientJsonField(result, "structuredContent", fallback: "{}"))
    }

    private func invokeMcp(request: String): JsonObject {
        let initialize = buildJsonRpcRequest(1, "initialize", JsonObject())
        let payload = "${encodeMcpFrame(initialize)}${encodeMcpFrame(request)}"
        let commandTemplate = resolveServiceCommand(config.serviceDir, config.workspaceRoot)
        let script = commandTemplate.replace("__PAYLOAD__", clientShellQuote(payload))
        let (status, stdoutBytes, stderrBytes) = executeWithOutput("bash",
            ["-lc", script],
            workingDirectory: Path(config.serviceDir),
            stdOut: Pipe,
            stdErr: Pipe)
        let stdout = String.fromUtf8(stdoutBytes)
        let stderr = String.fromUtf8(stderrBytes)
        if (status != 0) {
            throw IllegalArgumentException("service invocation failed: ${clientShortPreview(stderr, maxLines: 8)}")
        }
        let bodies = extractMcpBodies(stdout)
        if (bodies.isEmpty()) {
            throw IllegalArgumentException("service returned no MCP response: ${clientShortPreview(stderr, maxLines: 8)}")
        }
        return clientParseJsonObject(bodies[bodies.size - 1])
    }
}

// 子包内部工具函数副本（避免对根包循环依赖）
func clientJsonField(obj: JsonObject, key: String, fallback!: String = ""): String {
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

func clientParseJsonObject(body: String): JsonObject {
    if (body.trimAscii().isEmpty()) {
        return JsonObject()
    }
    return JsonValue.fromStr(body).asObject()
}

func clientShortPreview(text: String, maxLines!: Int64 = 8): String {
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

func clientShellQuote(text: String): String {
    return "'" + text.replace("'", "'\\''") + "'"
}
