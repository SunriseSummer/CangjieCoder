// 项目模板工具
package cangjiecoder.tools

import stdx.encoding.json.*
import cangjiecoder.json.*
import cangjiecoder.projects.*

public func handleListExamples(ctx: McpToolContext, _: JsonObject): String {
    let data = parseJsonObject(exampleProjectsJson(ctx.serviceRoot))
    return toolResultJson(true, "Listed example projects", data: data)
}

public func handleBootstrapJsonParser(ctx: McpToolContext, args: JsonObject): String {
    let message = bootstrapJsonParserProject(ctx.serviceRoot, ctx.workspaceRoot, jsonField(args, "path"))
    let ok = message.startsWith("Bootstrapped ")
    return toolMessageJson(ok, if (ok) { "Bootstrapped JsonParser example" } else { "JsonParser bootstrap did not complete" }, message)
}

public func handleBootstrapExample(ctx: McpToolContext, args: JsonObject): String {
    let projectId = jsonField(args, "project_id")
    let path = jsonField(args, "path")
    if (projectId.trimAscii().isEmpty()) {
        return toolMessageJson(false, "Missing project_id", "project_id is required. Use project.list_examples to see available projects.")
    }
    if (path.trimAscii().isEmpty()) {
        return toolMessageJson(false, "Missing path", "path is required. Specify the destination directory inside the workspace.")
    }
    let message = bootstrapExampleProject(ctx.serviceRoot, ctx.workspaceRoot, projectId, path)
    let ok = message.startsWith("Bootstrapped ")
    let summary = if (ok) { "Bootstrapped ${projectId}" } else { "Bootstrap did not complete for ${projectId}" }
    return toolMessageJson(ok, summary, message)
}
