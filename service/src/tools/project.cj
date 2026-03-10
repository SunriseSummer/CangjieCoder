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
