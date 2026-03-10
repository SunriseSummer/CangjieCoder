// 技能搜索工具
package cangjiecoder.tools

import stdx.encoding.json.*
import cangjiecoder.json.*
import cangjiecoder.skills.*

public func handleSkillsSearch(ctx: McpToolContext, args: JsonObject): String {
    let query = jsonField(args, "query")
    let registry = SkillRegistry(ctx.serviceRoot)
    let matches = registry.search(query, limit: 8)
    let data = parseJsonObject(skillsJson(matches))
    return toolResultJson(true, "Skills search completed", data: data)
}
