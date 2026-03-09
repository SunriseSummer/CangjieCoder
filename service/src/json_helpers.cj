package cangjiecoder

import std.collection.*
import std.convert.*
import stdx.encoding.json.*
import cangjiecoder.lsp.*

// 安全地从 JsonObject 中读取 String 值，统一处理 JsString 与其他类型
func jsonField(obj: JsonObject, key: String, fallback!: String = ""): String {
    match (obj.get(key)) {
        case Some(value) =>
            match (value.kind()) {
                case JsString => return value.asString().getValue()
                case _ => return value.toString()
            }
        case None =>
            return fallback
    }
}

// 空文本统一视为空对象，减少上层调用中的空串判定分支
func parseJsonObject(body: String): JsonObject {
    if (body.trimAscii().isEmpty()) {
        return JsonObject()
    }
    return JsonValue.fromStr(body).asObject()
}

// 从 JSON 对象提取整数字段，解析失败时返回 fallback
func parseJsonIntField(obj: JsonObject, key: String, fallback!: Int64 = 0): Int64 {
    let raw = jsonField(obj, key)
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return fallback
    }
    try {
        return Int64.parse(trimmed)
    } catch (e: Exception) {
        return fallback
    }
}

// 从 JSON 对象提取布尔字段，仅识别 "true"/"false"，其余返回 fallback
func parseJsonBoolField(obj: JsonObject, key: String, fallback!: Bool = false): Bool {
    let raw = jsonField(obj, key).trimAscii().toAsciiLower()
    if (raw.isEmpty()) {
        return fallback
    }
    if (raw == "true") {
        return true
    }
    if (raw == "false") {
        return false
    }
    return fallback
}

// 从 JSON 对象提取字符串数组，兼容单值字符串与非字符串元素
func jsonStringArrayField(obj: JsonObject, key: String): Array<String> {
    match (obj.get(key)) {
        case Some(value) =>
            match (value.kind()) {
                case JsArray =>
                    let items = value.asArray()
                    let results = ArrayList<String>()
                    var index: Int64 = 0
                    while (index < items.size()) {
                        match (items.get(index)) {
                            case Some(itemValue) =>
                                match (itemValue.kind()) {
                                    case JsString => results.add(itemValue.asString().getValue())
                                    case _ => results.add(itemValue.toString())
                                }
                            case None => ()
                        }
                        index += 1
                    }
                    return results.toArray()
                case JsString =>
                    return [value.asString().getValue()]
                case _ =>
                    return [value.toString()]
            }
        case None =>
            return []
    }
}

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

// 构造标准的 MCP 工具调用结果
func toolResultJson(ok: Bool, summary: String, data!: JsonValue = JsonObject()): String {
    let root = JsonObject()
    root.put("ok", JsonBool(ok))
    root.put("summary", JsonString(summary))
    root.put("data", data)
    return root.toString()
}

func toolMessageJson(ok: Bool, summary: String, message: String): String {
    let data = JsonObject()
    data.put("message", JsonString(message))
    return toolResultJson(ok, summary, data: data)
}

// 将外部命令执行结果序列化为 MCP 工具结果格式
func toolCommandResultJson(command: String,
                           arguments: Array<String>,
                           workingDirectory: String,
                           status: Int64,
                           stdout: String,
                           stderr: String): String {
    let argsJson = JsonArray()
    for (arg in arguments) {
        argsJson.add(JsonString(arg))
    }
    let data = JsonObject()
    data.put("command", JsonString(command))
    data.put("arguments", argsJson)
    data.put("workingDirectory", JsonString(workingDirectory))
    data.put("exitCode", JsonInt(status))
    data.put("stdout", JsonString(shortPreview(stdout, maxLines: WORKSPACE_COMMAND_OUTPUT_PREVIEW_LINES)))
    data.put("stderr", JsonString(shortPreview(stderr, maxLines: WORKSPACE_COMMAND_OUTPUT_PREVIEW_LINES)))
    let ok = status == 0
    let summary = if (ok) {
        "Command succeeded: ${command}"
    } else {
        "Command failed: ${command}"
    }
    return toolResultJson(ok, summary, data: data)
}

