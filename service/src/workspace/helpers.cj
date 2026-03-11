// 工作区路径辅助函数：目录检查、URI 解析、路径覆盖解析
package cangjiecoder.workspace

import std.fs.*
import stdx.encoding.json.*
import cangjiecoder.json.*

// file:// URI scheme 前缀（"file://" = 7 字符），路径从第 8 个字符（即 "/" ）开始
let FILE_URI_SCHEME: String = "file://"

// 检查路径是否为已存在的目录。
// 利用 Directory.isEmpty() 的异常行为：对目录返回 Bool（无论是否为空），对文件抛出异常。
public func isDirectory(path: String): Bool {
    if (!exists(path)) {
        return false
    }
    try {
        // Directory.isEmpty 对目录返回 true/false，对非目录抛出异常
        let _ = Directory.isEmpty(Path(path))
        return true
    } catch (_: Exception) {
        return false
    }
}

// 将 file:// URI 转换为本地文件路径（如 "file:///home/user" → "/home/user"）
public func fileUriToPath(uri: String): ?String {
    // 检查 "file:///" 确保 URI 包含绝对路径（第三个 / 是路径开头）
    if (uri.startsWith("file:///")) {
        // 跳过 "file://"（7 字符），保留路径开头的 "/"
        return uri[FILE_URI_SCHEME.size..uri.size]
    }
    return None
}

// 从 MCP initialize 请求参数中提取第一个 root 路径。
// 支持 MCP 协议中 roots 数组格式：[{"uri":"file:///path","name":"..."}]
public func extractFirstRootPath(params: JsonObject): ?String {
    match (params.get("roots")) {
        case Some(rootsValue) =>
            let rootsArray = rootsValue.asArray()
            if (rootsArray.size() > 0) {
                match (rootsArray.get(0)) {
                    case Some(firstRootValue) =>
                        let firstRoot = firstRootValue.asObject()
                        let uri = jsonField(firstRoot, "uri")
                        return fileUriToPath(uri)
                    case None => return None
                }
            }
            return None
        case None => return None
    }
}

// 解析工具参数中的 workspacePath 覆盖值。
// 如果参数中包含有效的 workspacePath 目录路径，则使用它替代默认工作区根目录。
public func resolveEffectiveWorkspaceRoot(defaultRoot: String, args: JsonObject): String {
    let overridePath = jsonField(args, "workspacePath").trimAscii()
    if (overridePath.isEmpty()) {
        return defaultRoot
    }
    if (!overridePath.startsWith("/")) {
        return defaultRoot
    }
    if (isDirectory(overridePath)) {
        return canonicalize(overridePath).toString()
    }
    return defaultRoot
}
