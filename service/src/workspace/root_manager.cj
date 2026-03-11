// 工作区根目录管理：set_root / get_root 业务逻辑
package cangjiecoder.workspace

import std.fs.*
import stdx.encoding.json.*
import cangjiecoder.common.*
import cangjiecoder.json.*

// workspace.set_root 业务逻辑：验证路径并返回 (规范化路径, 结果JSON)。
// 如果路径无效，返回 ("", 错误JSON)，调用方据此决定是否更新 McpRuntime.workspaceRoot。
public func workspaceSetRootJson(path: String): (String, String) {
    let trimmed = path.trimAscii()
    if (trimmed.isEmpty()) {
        return ("", toolMessageJson(false, "workspace.set_root requires a path",
            "path parameter must be a non-empty absolute directory path"))
    }
    if (!trimmed.startsWith("/")) {
        return ("", toolMessageJson(false, "workspace.set_root requires an absolute path",
            "Provided path is not absolute: ${trimmed}"))
    }
    if (!isDirectory(trimmed)) {
        return ("", toolMessageJson(false, "workspace.set_root target does not exist",
            "Directory does not exist: ${trimmed}"))
    }
    let canonicalPath = canonicalize(trimmed).toString()
    let data = JsonObject()
    data.put("workspaceRoot", JsonString(canonicalPath))
    return (canonicalPath, toolResultJson(true, "Workspace root updated", data: data))
}

// workspace.get_root 业务逻辑：返回当前工作区根目录的结果 JSON
public func workspaceGetRootJson(currentRoot: String): String {
    let data = JsonObject()
    data.put("workspaceRoot", JsonString(currentRoot))
    return toolResultJson(true, "Current workspace root", data: data)
}

// workspace.set_root 和 workspace.get_root 的占位处理函数。
// 实际逻辑在 mcp/handlers.cj 的 handleToolsCall 中直接处理（需访问 McpRuntime）。
public func handleWorkspaceRootPlaceholder(_: McpToolContext, _: JsonObject): String {
    return toolMessageJson(false, "Internal routing error",
        "workspace.set_root and workspace.get_root must be handled by McpRuntime, not the tool registry")
}
