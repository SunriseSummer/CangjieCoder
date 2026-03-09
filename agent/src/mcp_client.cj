package cangjiecoderagent

import std.collection.*
import std.convert.*
import std.fs.*
import std.process.*
import stdx.encoding.json.*

const MCP_HEADER_DELIMITER: String = "\r\n\r\n"
const MCP_CONTENT_LENGTH_HEADER: String = "Content-Length:"

func encodeMcpFrame(body: String): String {
    return "${MCP_CONTENT_LENGTH_HEADER} ${body.toArray().size}${MCP_HEADER_DELIMITER}${body}"
}

func extractMcpBodies(raw: String): Array<String> {
    let bodies = ArrayList<String>()
    var offset: Int64 = 0
    while (offset < raw.size) {
        // MCP stdio may emit multiple framed JSON-RPC responses in one stdout burst,
        // so decode them sequentially instead of assuming a single frame.
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

func buildJsonRpcRequest(id: Int64, method: String, params: JsonValue): String {
    let root = JsonObject()
    root.put("jsonrpc", JsonString("2.0"))
    root.put("id", JsonInt(id))
    root.put("method", JsonString(method))
    root.put("params", params)
    return root.toString()
}

func resolveServiceCommand(serviceDir: String, workspaceRoot: String): String {
    let releaseBinary = "${serviceDir}/target/release/bin/main"
    let debugBinary = "${serviceDir}/target/debug/bin/main"
    // Prefer an existing binary for speed, but preserve a source-only fallback so
    // the agent can still run against a fresh checkout.
    let command = if (exists(releaseBinary)) {
        shellQuote(releaseBinary)
    } else if (exists(debugBinary)) {
        shellQuote(debugBinary)
    } else {
        let runArgs = shellQuote("mcp-stdio --repo ${workspaceRoot}")
        return "cd ${shellQuote(serviceDir)} && printf '%s' __PAYLOAD__ | cjpm run --run-args ${runArgs}"
    }
    return "cd ${shellQuote(serviceDir)} && printf '%s' __PAYLOAD__ | ${command} mcp-stdio --repo ${shellQuote(workspaceRoot)}"
}

class ServiceClient {
    let config: AgentConfig

    public init(config: AgentConfig) {
        this.config = config
    }

    public func listToolsJson(): String {
        let response = invokeMcp(buildJsonRpcRequest(2, "tools/list", JsonObject()))
        return jsonField(response, "result")
    }

    public func callTool(name: String, arguments: JsonObject): JsonObject {
        let params = JsonObject()
        params.put("name", JsonString(name))
        params.put("arguments", arguments)
        let response = invokeMcp(buildJsonRpcRequest(2, "tools/call", params))
        let result = parseJsonObject(jsonField(response, "result", fallback: "{}"))
        return parseJsonObject(jsonField(result, "structuredContent", fallback: "{}"))
    }

    private func invokeMcp(request: String): JsonObject {
        let initialize = buildJsonRpcRequest(1, "initialize", JsonObject())
        // Each isolated stdio invocation begins with initialize so the service can
        // answer tool calls even when we do not keep a long-lived MCP process.
        let payload = "${encodeMcpFrame(initialize)}${encodeMcpFrame(request)}"
        let commandTemplate = resolveServiceCommand(config.serviceDir, config.workspaceRoot)
        let script = commandTemplate.replace("__PAYLOAD__", shellQuote(payload))
        let (status, stdoutBytes, stderrBytes) = executeWithOutput("bash",
            ["-lc", script],
            workingDirectory: Path(config.serviceDir),
            stdOut: Pipe,
            stdErr: Pipe)
        let stdout = String.fromUtf8(stdoutBytes)
        let stderr = String.fromUtf8(stderrBytes)
        if (status != 0) {
            throw IllegalArgumentException("service invocation failed: ${shortPreview(stderr, maxLines: 8)}")
        }
        let bodies = extractMcpBodies(stdout)
        if (bodies.isEmpty()) {
            throw IllegalArgumentException("service returned no MCP response: ${shortPreview(stderr, maxLines: 8)}")
        }
        // The final frame corresponds to the requested method because initialize
        // always runs first in the same payload.
        return parseJsonObject(bodies[bodies.size - 1])
    }
}
