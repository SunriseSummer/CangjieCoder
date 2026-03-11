// MCP 运行时、JSON-RPC 方法处理和 stdio 服务
// 本模块是 MCP 服务的顶层入口，负责将 JSON-RPC 请求分发到对应的方法处理函数，
// 管理工具注册表和运行时上下文，以及 stdio 帧级通信循环。
package cangjiecoder.mcp

import std.collection.*
import std.env.*
import std.fs.*
import stdx.encoding.json.*
import cangjiecoder.common.*
import cangjiecoder.json.*
import cangjiecoder.workspace.*

// POSIX write 系统调用声明（用于绕过仓颉 ConsoleWriter 的管道缓冲问题）
foreign func write(fd: Int32, buf: CPointer<UInt8>, count: UIntNative): IntNative

// 直接通过 POSIX write 系统调用写入 stdout（绕过所有缓冲层）
func writeStdoutDirect(content: String): Unit {
    let bytes = content.toArray()
    unsafe {
        var handle = acquireArrayRawData(bytes)
        var offset: Int64 = 0
        while (offset < bytes.size) {
            let n = write(1, CPointer<UInt8>(handle.pointer) + offset,
                          UIntNative(bytes.size - offset))
            if (Int64(n) <= 0) {
                break
            }
            offset += Int64(n)
        }
        releaseArrayRawData(handle)
    }
}

// ── MCP 工具调度 ─────────────────────────────────────

// 在工具注册表中查找并调用指定名称的工具处理函数。
// 未知工具或执行异常时返回标准化的错误结果。
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

// ── JSON-RPC 方法处理 ────────────────────────────────

// MCP 方法处理函数类型：接收运行时、请求 id、参数，返回 JSON-RPC 响应字符串
type McpMethodHandler = (McpRuntime, String, JsonObject) -> String

// 处理 initialize 请求：返回服务器能力声明和标识信息。
// 同时从客户端参数中提取 roots 信息，自动设置工作区路径。
func handleInitialize(runtime: McpRuntime, idJson: String, params: JsonObject): String {
    // 从客户端 initialize 参数中提取 roots，自动设置工作区路径
    if (!runtime.hasExplicitRepo) {
        if (let Some(rootPath) <- extractFirstRootPath(params)) {
            if (isDirectory(rootPath)) {
                try {
                    runtime.workspaceRoot = canonicalize(rootPath).toString()
                } catch (_: Exception) {
                    // canonicalize 失败（权限问题等），保持默认工作区
                }
            }
        }
    }

    let result = JsonObject()
    // 声明支持的能力：工具调用、提示词、资源访问
    let capabilities = JsonObject()
    capabilities.put("tools", JsonObject())
    capabilities.put("prompts", JsonObject())
    capabilities.put("resources", JsonObject())
    result.put("capabilities", capabilities)
    // 服务器标识
    let serverInfo = JsonObject()
    serverInfo.put("name", JsonString("CangjieCoder"))
    serverInfo.put("version", JsonString(APP_VERSION))
    result.put("serverInfo", serverInfo)
    return jsonRpcResult(idJson, result.toString())
}

// 处理 ping 请求：返回 pong 心跳响应
func handlePing(_: McpRuntime, idJson: String, _: JsonObject): String {
    return jsonRpcResult(idJson, "{\"pong\":true}")
}

// 处理 initialized 通知：协议要求的确认响应
func handleNotificationsInitialized(_: McpRuntime, idJson: String, _: JsonObject): String {
    return jsonRpcResult(idJson, "null")
}

// 处理 tools/list 请求：返回所有已注册工具的元数据定义
func handleToolsList(_: McpRuntime, idJson: String, _: JsonObject): String {
    return jsonRpcResult(idJson, toolDefinitionsJson())
}

// 处理 tools/call 请求：解析工具名和参数，调度到具体的工具处理函数。
// 支持 workspacePath 参数覆盖工作区路径，以及 workspace.set_root/get_root 动态管理工作区。
func handleToolsCall(runtime: McpRuntime, idJson: String, params: JsonObject): String {
    let toolName = jsonField(params, "name")
    let toolArgs = match (params.get("arguments")) {
        case Some(value) => value.asObject()
        case None => JsonObject()
    }

    // workspace.set_root：动态设置会话级工作区根目录
    if (toolName == "workspace.set_root") {
        let (newRoot, toolResult) = workspaceSetRootJson(jsonField(toolArgs, "path"))
        if (!newRoot.isEmpty()) {
            runtime.workspaceRoot = newRoot
        }
        return jsonRpcResult(idJson, mcpToolCallResultJson(toolResult))
    }

    // workspace.get_root：查询当前工作区根目录
    if (toolName == "workspace.get_root") {
        let toolResult = workspaceGetRootJson(runtime.workspaceRoot)
        return jsonRpcResult(idJson, mcpToolCallResultJson(toolResult))
    }

    // 支持 workspacePath 参数覆盖当前调用的工作区路径
    let effectiveWorkspaceRoot = resolveEffectiveWorkspaceRoot(runtime.workspaceRoot, toolArgs)

    let ctx = McpToolContext(effectiveWorkspaceRoot, runtime.serviceRoot)
    let toolResult = callMcpTool(runtime.toolRegistry, ctx, toolName, toolArgs)
    return jsonRpcResult(idJson, mcpToolCallResultJson(toolResult))
}

// 构建 JSON-RPC 方法注册表，映射方法名到处理函数
public func buildMcpMethodRegistry(): HashMap<String, McpMethodHandler> {
    let registry = HashMap<String, McpMethodHandler>()
    registry["initialize"] = handleInitialize
    registry["ping"] = handlePing
    registry["notifications/initialized"] = handleNotificationsInitialized
    registry["tools/list"] = handleToolsList
    registry["tools/call"] = handleToolsCall
    return registry
}

// ── McpRuntime 核心运行时 ────────────────────────────

// MCP 服务运行时：维护工作区路径、方法注册表和工具注册表，
// 负责接收和分发 JSON-RPC 请求
public class McpRuntime {
    public var workspaceRoot: String      // 用户工作区根目录（可通过 initialize roots 或 set_root 动态修改）
    public let serviceRoot: String        // 服务自身所在目录（用于定位内置资源）
    public let hasExplicitRepo: Bool      // 是否通过 --repo 显式指定了工作区
    let methodRegistry: HashMap<String, McpMethodHandler>
    public let toolRegistry: HashMap<String, McpToolHandler>

    public init(workspaceRoot: String, serviceRoot!: String = "", hasExplicitRepo!: Bool = false) {
        this.workspaceRoot = workspaceRoot
        this.serviceRoot = if (serviceRoot.trimAscii().isEmpty()) { workspaceRoot } else { serviceRoot }
        this.hasExplicitRepo = hasExplicitRepo
        this.methodRegistry = buildMcpMethodRegistry()
        this.toolRegistry = buildMcpToolRegistry()
    }

    // 处理单个 MCP JSON-RPC 请求：解析方法名、查找处理函数、执行并返回响应。
    // 对于通知（无 id 的请求），返回 None 表示不需要响应。
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

            // 通知（无 id）不需要响应
            if (!hasId) {
                return None
            }

            match (methodRegistry.get(method)) {
                case Some(handler) => return Some(handler(this, idJson, params))
                case None => return Some(jsonRpcError(idJson, -32601, "Unsupported MCP method: ${method}"))
            }
        } catch (e: Exception) {
            return Some(jsonRpcError("null", -32700,
                "Failed to parse MCP request: ${shortPreview(e.toString(), maxLines: 4)}"))
        }
    }
}

// ── stdio 服务循环 ───────────────────────────────────

// 启动 MCP stdio 服务：循环读取 stdin 帧 → 处理请求 → 写回响应帧
public func startMcpStdioServer(runtime: McpRuntime): Unit {
    let reader = getStdIn()
    while (true) {
        match (readStdioFrame(reader)) {
            case Some(body) =>
                match (runtime.handleRequest(body)) {
                    case Some(response) =>
                        writeStdoutDirect(encodeMcpFrame(response))
                    case None => ()
                }
            case None =>
                break
        }
    }
}

// ── 工厂函数 ─────────────────────────────────────────

// 创建 MCP 运行时实例，serviceRoot 默认等于 workspaceRoot
public func createMcpRuntime(workspaceRoot: String, serviceRoot!: String = "",
                      hasExplicitRepo!: Bool = false): McpRuntime {
    let effectiveServiceRoot = if (serviceRoot.trimAscii().isEmpty()) { workspaceRoot } else { serviceRoot }
    return McpRuntime(workspaceRoot, serviceRoot: effectiveServiceRoot,
        hasExplicitRepo: hasExplicitRepo)
}
