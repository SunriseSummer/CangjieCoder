package cangjiecoder.tools

import std.convert.*
import stdx.encoding.json.*

/**
 * 工具参数解析辅助：从 OpenAI function-calling 的 `arguments` JSON 文本
 * 中安全提取字段，失败返回默认值或 None
 */
public func parseArgs(argumentsJson: String): JsonObject {
    let text = argumentsJson.trimAscii()
    if (text.isEmpty()) {
        return JsonObject()
    }
    try {
        let jv = JsonValue.fromStr(text)
        match (jv.kind()) {
            case JsObject => return jv.asObject()
            case _ => return JsonObject()
        }
    } catch (_: Exception) {
        return JsonObject()
    }
}

public func getString(obj: JsonObject, key: String, default!: String = ""): String {
    if (let Some(v) <- obj.get(key)) {
        match (v.kind()) {
            case JsString => return v.asString().getValue()
            case JsInt => return v.asInt().getValue().toString()
            case JsFloat => return v.asFloat().getValue().toString()
            case JsBool => return v.asBool().getValue().toString()
            case _ => return default
        }
    }
    return default
}

public func getInt(obj: JsonObject, key: String, default!: Int64 = 0): Int64 {
    if (let Some(v) <- obj.get(key)) {
        match (v.kind()) {
            case JsInt => return v.asInt().getValue()
            case JsString =>
                let text = v.asString().getValue()
                match (Int64.tryParse(text)) {
                    case Some(parsed) => return parsed
                    case None => return default
                }
            case _ => return default
        }
    }
    return default
}

public func getPositiveInt(obj: JsonObject, key: String, default!: Int64): Int64 {
    let value = getInt(obj, key, default: default)
    return if (value > 0) {
        value
    } else {
        default
    }
}

public func getBool(obj: JsonObject, key: String, default!: Bool = false): Bool {
    if (let Some(v) <- obj.get(key)) {
        match (v.kind()) {
            case JsBool => return v.asBool().getValue()
            case JsString => return v.asString().getValue() == "true"
            case _ => return default
        }
    }
    return default
}

public func requireString(obj: JsonObject, key: String): ?String {
    let value = getString(obj, key)
    return if (value.isEmpty()) {
        None
    } else {
        Some(value)
    }
}
