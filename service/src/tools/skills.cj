// 技能搜索工具
package cangjiecoder.tools

import stdx.encoding.json.*
import cangjiecoder.common.*
import cangjiecoder.json.*
import cangjiecoder.skills.*

public func handleSkillsSearch(ctx: McpToolContext, args: JsonObject): String {
    let query = jsonField(args, "query")
    let registry = SkillRegistry(ctx.serviceRoot)
    let matches = registry.search(query, limit: 8)
    let data = parseJsonObject(skillsJson(matches))
    return toolResultJson(true, "Skills search completed", data: data)
}

// 批量搜索多个技能查询，一次请求返回多组结果，减少网络往返和 Token 消耗
public func handleSkillsBatchSearch(ctx: McpToolContext, args: JsonObject): String {
    let queries = jsonStringArrayField(args, "queries")
    if (queries.isEmpty()) {
        return toolMessageJson(false, "Batch search failed", "queries must be a non-empty array of search strings")
    }
    let registry = SkillRegistry(ctx.serviceRoot)
    let resultsArray = JsonArray()
    for (query in queries) {
        let matches = registry.search(query, limit: 5)
        let queryResult = JsonObject()
        queryResult.put("query", JsonString(query))
        let matchesArray = JsonArray()
        for (skill in matches) {
            let item = JsonObject()
            item.put("id", JsonString(skill.id))
            item.put("name", JsonString(skill.name))
            item.put("description", JsonString(skill.description))
            matchesArray.add(item)
        }
        queryResult.put("matches", matchesArray)
        resultsArray.add(queryResult)
    }
    let data = JsonObject()
    data.put("results", resultsArray)
    data.put("queryCount", JsonInt(queries.size))
    return toolResultJson(true, "Batch search completed for ${queries.size} queries", data: data)
}

// 根据查询生成可直接用于 AI 提示词的技能上下文文本
// 返回紧凑的上下文块，AI 可直接嵌入 system prompt，节省 Token
public func handleSkillsPromptContext(ctx: McpToolContext, args: JsonObject): String {
    let query = jsonField(args, "query")
    let limit = parseJsonIntField(args, "limit", fallback: 3)
    let registry = SkillRegistry(ctx.serviceRoot)
    let context = registry.buildPromptContext(query, limit: limit)
    let data = JsonObject()
    data.put("query", JsonString(query))
    data.put("context", JsonString(context))
    data.put("isEmpty", JsonBool(context.isEmpty()))
    return toolResultJson(true, if (context.isEmpty()) { "No matching skills found" } else { "Prompt context generated" }, data: data)
}
