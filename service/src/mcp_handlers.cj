// MCP 运行时、JSON-RPC 方法处理和 stdio 服务
package cangjiecoder

import std.collection.*
import std.env.*
import stdx.encoding.json.*
import cangjiecoder.common.*
import cangjiecoder.json.*
import cangjiecoder.mcp.*
import cangjiecoder.tools.*

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

// ---- MCP JSON-RPC 方法处理 ----

type McpMethodHandler = (McpRuntime, String, JsonObject) -> String

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
    let ctx = McpToolContext(runtime.workspaceRoot, runtime.serviceRoot)
    return jsonRpcResult(idJson, mcpToolCallResultJson(callMcpTool(runtime.toolRegistry, ctx, toolName, toolArgs)))
}

func buildMcpMethodRegistry(): HashMap<String, McpMethodHandler> {
    let registry = HashMap<String, McpMethodHandler>()
    registry["initialize"] = handleInitialize
    registry["ping"] = handlePing
    registry["notifications/initialized"] = handleNotificationsInitialized
    registry["tools/list"] = handleToolsList
    registry["tools/call"] = handleToolsCall
    return registry
}

// ---- McpRuntime ----

class McpRuntime {
    public let workspaceRoot: String
    public let serviceRoot: String
    let methodRegistry: HashMap<String, McpMethodHandler>
    public let toolRegistry: HashMap<String, McpToolHandler>

    public init(workspaceRoot: String, serviceRoot!: String = "") {
        this.workspaceRoot = workspaceRoot
        this.serviceRoot = if (serviceRoot.trimAscii().isEmpty()) { workspaceRoot } else { serviceRoot }
        this.methodRegistry = buildMcpMethodRegistry()
        this.toolRegistry = buildMcpToolRegistry()
    }

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

func startMcpStdioServer(runtime: McpRuntime): Unit {
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

func createMcpRuntime(workspaceRoot: String, serviceRoot!: String = ""): McpRuntime {
    let effectiveServiceRoot = if (serviceRoot.trimAscii().isEmpty()) { workspaceRoot } else { serviceRoot }
    return McpRuntime(workspaceRoot, serviceRoot: effectiveServiceRoot)
}
