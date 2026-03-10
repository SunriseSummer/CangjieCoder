// JSON 工具函数：通用 JSON 解析、字段提取、序列化辅助
// 提供安全的 JSON 字段读取（字符串/整数/布尔/数组）、MCP 工具结果封装，
// 以及命令执行结果的结构化序列化能力。
package cangjiecoder.json

import std.collection.*
import std.convert.*
import stdx.encoding.json.*

// ── JSON 字段安全提取 ────────────────────────────────

// 安全地从 JsonObject 中读取 String 值。
// JsString 类型取原始值；其他类型转为字符串表示；缺失键返回 fallback。
public func jsonField(obj: JsonObject, key: String, fallback!: String = ""): String {
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

// 将 JSON 字符串解析为 JsonObject。
// 空文本统一视为空对象，减少上层调用中的空串判定分支。
public func parseJsonObject(body: String): JsonObject {
    if (body.trimAscii().isEmpty()) {
        return JsonObject()
    }
    return JsonValue.fromStr(body).asObject()
}

// 从 JSON 对象提取整数字段，解析失败或字段缺失时返回 fallback
public func parseJsonIntField(obj: JsonObject, key: String, fallback!: Int64 = 0): Int64 {
    let raw = jsonField(obj, key)
    let trimmed = raw.trimAscii()
    if (trimmed.isEmpty()) {
        return fallback
    }
    try {
        return Int64.parse(trimmed)
    } catch (_: Exception) {
        return fallback
    }
}

// 从 JSON 对象提取布尔字段，仅识别 "true"/"false" 字面量，其余返回 fallback
public func parseJsonBoolField(obj: JsonObject, key: String, fallback!: Bool = false): Bool {
    let raw = jsonField(obj, key).trimAscii().toAsciiLower()
    if (raw == "true") {
        return true
    }
    if (raw == "false") {
        return false
    }
    return fallback
}

// 从 JSON 对象提取字符串数组。
// 兼容三种输入形式：JSON 数组、单个字符串值、非字符串元素（转为 toString）。
public func jsonStringArrayField(obj: JsonObject, key: String): Array<String> {
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

// ── MCP 工具结果封装 ─────────────────────────────────

// 构造标准的 MCP 工具调用结果 JSON 字符串（含 ok/summary/data 字段）
public func toolResultJson(ok: Bool, summary: String, data!: JsonValue = JsonObject()): String {
    let root = JsonObject()
    root.put("ok", JsonBool(ok))
    root.put("summary", JsonString(summary))
    root.put("data", data)
    return root.toString()
}

// 构造附带消息文本的 MCP 工具结果
public func toolMessageJson(ok: Bool, summary: String, message: String): String {
    let data = JsonObject()
    data.put("message", JsonString(message))
    return toolResultJson(ok, summary, data: data)
}

// 将外部命令执行结果序列化为 MCP 工具结果格式，
// 包含命令名、参数、工作目录、退出码、截取后的标准输出/标准错误
public func toolCommandResultJson(command: String,
                           arguments: Array<String>,
                           workingDirectory: String,
                           status: Int64,
                           stdout: String,
                           stderr: String,
                           maxLines!: Int64 = 20): String {
    let argsJson = JsonArray()
    for (arg in arguments) {
        argsJson.add(JsonString(arg))
    }
    let data = JsonObject()
    data.put("command", JsonString(command))
    data.put("arguments", argsJson)
    data.put("workingDirectory", JsonString(workingDirectory))
    data.put("exitCode", JsonInt(status))
    data.put("stdout", JsonString(jsonShortPreview(stdout, maxLines: maxLines)))
    data.put("stderr", JsonString(jsonShortPreview(stderr, maxLines: maxLines)))
    let ok = status == 0
    let summary = if (ok) { "Command succeeded: ${command}" } else { "Command failed: ${command}" }
    return toolResultJson(ok, summary, data: data)
}

// ── 子包内部工具函数 ─────────────────────────────────

// 子包内部的文本预览截取（跳过空行，最多保留 maxLines 行），
// 避免对根包 shortPreview 的循环依赖
func jsonShortPreview(text: String, maxLines!: Int64 = 8): String {
    let lines = ArrayList<String>()
    var count = 0
    for (line in text.lines()) {
        if (line.trimAscii().isEmpty()) {
            continue
        }
        lines.add(line)
        count += 1
        if (count >= maxLines) {
            break
        }
    }
    return String.join(lines.toArray(), delimiter: "\n")
}
