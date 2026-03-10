package cangjiecoder

import std.io.*
import stdx.encoding.json.*
import stdx.net.http.*
import cangjiecoder.common.*
import cangjiecoder.json.*
import cangjiecoder.lsp.*
import cangjiecoder.skills.*
import cangjiecoder.projects.*
import cangjiecoder.analysis.*

// 启动 HTTP API 服务，注册所有工作区/LSP/MCP 路由
func startServer(config: AppConfig): Unit {
    let runtime = createMcpRuntime(config.workspaceRoot, serviceRoot: config.serviceRoot)
    let skillRegistry = SkillRegistry(runtime.serviceRoot)
    let server = ServerBuilder().addr(config.host).port(config.port).build()

    server.distributor.register("/health", {
        ctx =>
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body("{\"status\":\"ok\"}")
    })

    server.distributor.register("/projects/examples", {
        ctx =>
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(exampleProjectsJson(config.serviceRoot))
    })

    server.distributor.register("/skills", {
        ctx =>
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(skillsJson(skillRegistry.list(limit: 200)))
    })

    server.distributor.register("/skills/search", {
        ctx =>
        let request = parseJsonObject(StringReader(ctx.request.body).readToEnd())
        let query = jsonField(request, "query")
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(skillsJson(skillRegistry.search(query, limit: 8)))
    })

    server.distributor.register("/analyze", {
        ctx =>
        let request = parseJsonObject(StringReader(ctx.request.body).readToEnd())
        let path = jsonField(request, "path")
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(analysisJson(analyzeCangjieFile(config.workspaceRoot, path)))
    })

    server.distributor.register("/bootstrap/json-parser", {
        ctx =>
        let request = parseJsonObject(StringReader(ctx.request.body).readToEnd())
        let path = jsonField(request, "path")
        let root = JsonObject()
        root.put("message", JsonString(bootstrapJsonParserProject(config.serviceRoot, config.workspaceRoot, path)))
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(root.toString())
    })

    server.distributor.register("/workspace/create-file", {
        ctx =>
        let request = parseJsonObject(StringReader(ctx.request.body).readToEnd())
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(workspaceCreateFileJson(config.workspaceRoot,
                jsonField(request, "path"),
                jsonField(request, "content"),
                overwrite: parseJsonBoolField(request, "overwrite", fallback: false)))
    })

    server.distributor.register("/lsp/status", {
        ctx =>
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(lspStatusJson(inspectLspStatus(config.workspaceRoot)))
    })

    server.distributor.register("/lsp/probe", {
        ctx =>
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(lspProbeJson(probeLspServer(config.workspaceRoot)))
    })

    server.distributor.register("/lsp/document-symbols", {
        ctx =>
        let request = parseJsonObject(StringReader(ctx.request.body).readToEnd())
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(lspQueryJson(queryLspDocumentSymbols(config.workspaceRoot, jsonField(request, "path"))))
    })

    server.distributor.register("/lsp/workspace-symbols", {
        ctx =>
        let request = parseJsonObject(StringReader(ctx.request.body).readToEnd())
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(lspQueryJson(queryLspWorkspaceSymbols(config.workspaceRoot, jsonField(request, "query"))))
    })

    server.distributor.register("/lsp/definition", {
        ctx =>
        let request = parseJsonObject(StringReader(ctx.request.body).readToEnd())
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(lspQueryJson(queryLspDefinition(config.workspaceRoot,
                jsonField(request, "path"),
                parseJsonIntField(request, "line", fallback: 0),
                parseJsonIntField(request, "column", fallback: 0))))
    })

    server.distributor.register("/ast/edit", {
        ctx =>
        let request = parseJsonObject(StringReader(ctx.request.body).readToEnd())
        let root = JsonObject()
        root.put("message", JsonString(editAstNode(config.workspaceRoot,
            jsonField(request, "path"),
            jsonField(request, "nodeType"),
            jsonField(request, "replacement"),
            index: parseJsonIntField(request, "index", fallback: 0))))
        ctx.responseBuilder
            .header("Content-Type", "application/json")
            .body(root.toString())
    })

    server.distributor.register("/mcp", {
        ctx =>
        let body = StringReader(ctx.request.body).readToEnd()
        match (runtime.handleRequest(body)) {
            case Some(response) =>
                ctx.responseBuilder
                    .header("Content-Type", "application/json")
                    .body(response)
            case None =>
                ctx.responseBuilder
                    .body("")
        }
    })

    println("CangjieCoder server listening on http://${config.host}:${config.port}")
    server.serve()
}
