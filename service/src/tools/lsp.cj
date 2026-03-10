// LSP 查询工具
package cangjiecoder.tools

import stdx.encoding.json.*
import cangjiecoder.json.*
import cangjiecoder.lsp.*

public func handleLspStatus(ctx: McpToolContext, _: JsonObject): String {
    let status = parseJsonObject(lspStatusJson(inspectLspStatus(ctx.workspaceRoot)))
    return toolResultJson(true, "Loaded Cangjie LSP status", data: status)
}

public func handleLspProbe(ctx: McpToolContext, _: JsonObject): String {
    return lspQueryToolResult(lspProbeJson(probeLspServer(ctx.workspaceRoot)),
        "LSP probe succeeded", "LSP probe did not complete cleanly")
}

public func handleLspDocumentSymbols(ctx: McpToolContext, args: JsonObject): String {
    return lspQueryToolResult(
        lspQueryJson(queryLspDocumentSymbols(ctx.workspaceRoot, jsonField(args, "path"))),
        "LSP document symbols loaded", "LSP document symbol query failed")
}

public func handleLspWorkspaceSymbols(ctx: McpToolContext, args: JsonObject): String {
    return lspQueryToolResult(
        lspQueryJson(queryLspWorkspaceSymbols(ctx.workspaceRoot, jsonField(args, "query"))),
        "LSP workspace symbols loaded", "LSP workspace symbol query failed")
}

public func handleLspDefinition(ctx: McpToolContext, args: JsonObject): String {
    return lspQueryToolResult(
        lspQueryJson(queryLspDefinition(ctx.workspaceRoot,
            jsonField(args, "path"),
            parseJsonIntField(args, "line", fallback: 0),
            parseJsonIntField(args, "column", fallback: 0))),
        "LSP definition loaded", "LSP definition query failed")
}
