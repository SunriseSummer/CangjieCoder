// MCP 工具辅助函数（LSP 结果封装）
package cangjiecoder.tools

import cangjiecoder.json.*

// 将 LSP 查询结果包装为标准工具结果
public func lspQueryToolResult(queryJson: String, okSummary: String, failSummary: String): String {
    let result = parseJsonObject(queryJson)
    let ok = jsonField(result, "success") == "true"
    return toolResultJson(ok, if (ok) { okSummary } else { failSummary }, data: result)
}
