// LSP 查询工具处理函数
package cangjiecoder.lsp

import stdx.encoding.json.*
import cangjiecoder.common.*
import cangjiecoder.json.*

// ── LSP 领域 JSON 序列化 ─────────────────────────────

func lspStatusToJson(status: LspStatus): String {
    let root = JsonObject()
    root.put("available", JsonBool(status.available))
    root.put("command", JsonString(status.command))
    root.put("summary", JsonString(status.summary))
    root.put("sourceHint", JsonString(status.sourceHint))
    return root.toString()
}

func lspProbeToJson(result: LspProbeResult): String {
    let root = JsonObject()
    root.put("available", JsonBool(result.available))
    root.put("success", JsonBool(result.success))
    root.put("command", JsonString(result.command))
    root.put("summary", JsonString(result.summary))
    root.put("responsePreview", JsonString(result.responsePreview))
    return root.toString()
}

func lspQueryToJson(result: LspQueryResult): String {
    let root = JsonObject()
    root.put("available", JsonBool(result.available))
    root.put("success", JsonBool(result.success))
    root.put("command", JsonString(result.command))
    root.put("method", JsonString(result.method))
    root.put("summary", JsonString(result.summary))
    root.put("responsePreview", JsonString(result.responsePreview))
    root.put("result", lspResultToJsonValue(result.resultJson))
    return root.toString()
}

// ── 工具处理函数 ─────────────────────────────────────

// 将 LSP 查询结果包装为标准工具结果
public func lspQueryToolResult(queryJson: String, okSummary: String, failSummary: String): String {
    let result = parseJsonObject(queryJson)
    let ok = jsonField(result, "success") == "true"
    return toolResultJson(ok, if (ok) { okSummary } else { failSummary }, data: result)
}

public func handleLspStatus(ctx: McpToolContext, _: JsonObject): String {
    let status = parseJsonObject(lspStatusToJson(inspectLspStatus(ctx.workspaceRoot)))
    return toolResultJson(true, "Loaded Cangjie LSP status", data: status)
}

public func handleLspProbe(ctx: McpToolContext, _: JsonObject): String {
    return lspQueryToolResult(lspProbeToJson(probeLspServer(ctx.workspaceRoot)),
        "LSP probe succeeded", "LSP probe did not complete cleanly")
}

public func handleLspDocumentSymbols(ctx: McpToolContext, args: JsonObject): String {
    return lspQueryToolResult(
        lspQueryToJson(queryLspDocumentSymbols(ctx.workspaceRoot, jsonField(args, "path"))),
        "LSP document symbols loaded", "LSP document symbol query failed")
}

public func handleLspWorkspaceSymbols(ctx: McpToolContext, args: JsonObject): String {
    return lspQueryToolResult(
        lspQueryToJson(queryLspWorkspaceSymbols(ctx.workspaceRoot, jsonField(args, "query"))),
        "LSP workspace symbols loaded", "LSP workspace symbol query failed")
}

public func handleLspDefinition(ctx: McpToolContext, args: JsonObject): String {
    return lspQueryToolResult(
        lspQueryToJson(queryLspDefinition(ctx.workspaceRoot,
            jsonField(args, "path"),
            parseJsonIntField(args, "line", fallback: 0),
            parseJsonIntField(args, "column", fallback: 0))),
        "LSP definition loaded", "LSP definition query failed")
}
