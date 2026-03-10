// 领域 JSON 序列化：将领域对象转换为 JSON 字符串
package cangjiecoder

import stdx.encoding.json.*
import cangjiecoder.lsp.*
import cangjiecoder.skills.*
import cangjiecoder.projects.*
import cangjiecoder.analysis.*

// 将 SkillRecord 数组序列化为 JSON 字符串
func skillsJson(skills: Array<SkillRecord>): String {
    let array = JsonArray()
    for (skill in skills) {
        let item = JsonObject()
        item.put("id", JsonString(skill.id))
        item.put("name", JsonString(skill.name))
        item.put("description", JsonString(skill.description))
        item.put("preview", JsonString(skill.preview))
        item.put("path", JsonString(skill.path))
        array.add(item)
    }
    let root = JsonObject()
    root.put("skills", array)
    return root.toString()
}

// 将 AnalysisResult 序列化为 JSON 字符串
func analysisJson(result: AnalysisResult): String {
    let root = JsonObject()
    root.put("engine", JsonString(result.engine))
    root.put("success", JsonBool(result.success))
    root.put("summary", JsonString(result.summary))
    root.put("output", JsonString(result.output))
    return root.toString()
}

// 将 example 项目列表序列化为 JSON 字符串
func exampleProjectsJson(serviceRoot: String): String {
    let array = JsonArray()
    for (project in listExampleProjects(serviceRoot)) {
        let item = JsonObject()
        item.put("id", JsonString(project.id))
        item.put("name", JsonString(project.name))
        item.put("description", JsonString(project.description))
        item.put("templatePath", JsonString(project.templatePath))
        array.add(item)
    }
    let root = JsonObject()
    root.put("projects", array)
    return root.toString()
}

func lspStatusJson(status: LspStatus): String {
    let root = JsonObject()
    root.put("available", JsonBool(status.available))
    root.put("command", JsonString(status.command))
    root.put("summary", JsonString(status.summary))
    root.put("sourceHint", JsonString(status.sourceHint))
    return root.toString()
}

func lspProbeJson(result: LspProbeResult): String {
    let root = JsonObject()
    root.put("available", JsonBool(result.available))
    root.put("success", JsonBool(result.success))
    root.put("command", JsonString(result.command))
    root.put("summary", JsonString(result.summary))
    root.put("responsePreview", JsonString(result.responsePreview))
    return root.toString()
}

func lspQueryJson(result: LspQueryResult): String {
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

