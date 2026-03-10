// MCP 工具共享类型与辅助函数
package cangjiecoder.tools

import cangjiecoder.json.*
import stdx.encoding.json.*

// MCP 工具上下文 —— 每次 tools/call 携带的运行时环境
public struct McpToolContext {
    public McpToolContext(public let workspaceRoot: String,
                          public let serviceRoot: String) {}
}

// MCP 工具处理函数类型
public type McpToolHandler = (McpToolContext, JsonObject) -> String

// 将 LSP 查询结果包装为标准工具结果
public func lspQueryToolResult(queryJson: String, okSummary: String, failSummary: String): String {
    let result = parseJsonObject(queryJson)
    let ok = jsonField(result, "success") == "true"
    return toolResultJson(ok, if (ok) { okSummary } else { failSummary }, data: result)
}
