// AST 解析/查询/编辑工具 + 代码分析工具
package cangjiecoder.tools

import stdx.encoding.json.*
import cangjiecoder.common.*
import cangjiecoder.json.*
import cangjiecoder.analysis.*
import cjtreesitter.*

// 使用内置 tree-sitter 解析仓颉源码并返回 S-expression
public func handleAstParse(ctx: McpToolContext, args: JsonObject): String {
    let path = jsonField(args, "path")
    if (let Some(fullPath) <- ensureWorkspacePath(ctx.workspaceRoot, path)) {
        let source = readTextFile(fullPath)
        let sexp = parseSexp(source)
        if (sexp.startsWith("error:")) {
            return toolMessageJson(false, "AST parse failed", sexp)
        }
        let data = JsonObject()
        data.put("path", JsonString(workspaceRelativePath(ctx.workspaceRoot, fullPath)))
        data.put("sexp", JsonString(sexp))
        return toolResultJson(true, "AST parse completed", data: data)
    }
    return toolMessageJson(false, "AST parse failed", "Path does not exist or escapes repository root: ${path}")
}

// 查询指定类型的 AST 节点
public func handleAstQueryNodes(ctx: McpToolContext, args: JsonObject): String {
    let path = jsonField(args, "path")
    let nodeType = jsonField(args, "nodeType")
    if (let Some(fullPath) <- ensureWorkspacePath(ctx.workspaceRoot, path)) {
        let source = readTextFile(fullPath)
        let nodes = queryNodes(source, nodeType)
        let data = JsonObject()
        data.put("path", JsonString(workspaceRelativePath(ctx.workspaceRoot, fullPath)))
        data.put("nodeType", JsonString(nodeType))
        data.put("matchCount", JsonInt(nodes.size))
        data.put("nodes", JsonValue.fromStr(nodeInfoArrayToJson(nodes)))
        return toolResultJson(true, "Found ${nodes.size} node(s) of type ${nodeType}", data: data)
    }
    return toolMessageJson(false, "AST query failed", "Path does not exist or escapes repository root: ${path}")
}

// 列出源文件中的命名 AST 节点概览
public func handleAstListNodes(ctx: McpToolContext, args: JsonObject): String {
    let path = jsonField(args, "path")
    let maxDepth = parseJsonIntField(args, "maxDepth", fallback: 4)
    if (let Some(fullPath) <- ensureWorkspacePath(ctx.workspaceRoot, path)) {
        let source = readTextFile(fullPath)
        let nodes = listNamedNodes(source, maxDepth: maxDepth)
        let data = JsonObject()
        data.put("path", JsonString(workspaceRelativePath(ctx.workspaceRoot, fullPath)))
        data.put("nodeCount", JsonInt(nodes.size))
        data.put("nodes", JsonValue.fromStr(nodeInfoArrayToJson(nodes)))
        return toolResultJson(true, "Listed ${nodes.size} named AST node(s)", data: data)
    }
    return toolMessageJson(false, "AST list failed", "Path does not exist or escapes repository root: ${path}")
}

// 通过 tree-sitter 定位 AST 节点并替换
public func handleEditAstNode(ctx: McpToolContext, args: JsonObject): String {
    // 尝试备份，路径无效时安全跳过
    if (let Some(fullPath) <- ensureWorkspacePath(ctx.workspaceRoot, jsonField(args, "path"))) {
        globalBackupStore.backup(fullPath)
    }
    let message = editAstNode(ctx.workspaceRoot,
        jsonField(args, "path"),
        jsonField(args, "nodeType"),
        jsonField(args, "replacement"),
        index: parseJsonIntField(args, "index", fallback: 0))
    let ok = astEditSucceeded(message)
    return toolMessageJson(ok, if (ok) { "AST node edit completed" } else { "AST node edit failed" }, message)
}

// 运行 tree-sitter/cjlint/cjc 逐级分析
public func handleAnalyzeFile(ctx: McpToolContext, args: JsonObject): String {
    let result = analyzeCangjieFile(ctx.workspaceRoot, jsonField(args, "path"))
    let data = parseJsonObject(analysisJson(result))
    return toolResultJson(result.success, result.summary, data: data)
}
