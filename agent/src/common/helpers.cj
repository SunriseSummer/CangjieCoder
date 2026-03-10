// 共享工具函数：JSON 解析、字符串处理等各模块复用的辅助逻辑
package cangjiecoderagent.common

import std.collection.*
import stdx.encoding.json.*

public func jsonField(obj: JsonObject, key: String, fallback!: String = ""): String {
    match (obj.get(key)) {
        case Some(value) =>
            match (value.kind()) {
                case JsString => return value.asString().getValue()
                case _ => return value.toString()
            }
        case None => return fallback
    }
}

public func parseJsonObject(body: String): JsonObject {
    if (body.trimAscii().isEmpty()) {
        return JsonObject()
    }
    return JsonValue.fromStr(body).asObject()
}

public func shortPreview(text: String, maxLines!: Int64 = 8): String {
    let lines = ArrayList<String>()
    var count: Int64 = 0
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

public func extractStructuredData(result: JsonObject): JsonObject {
    return parseJsonObject(jsonField(result, "data", fallback: "{}"))
}

public func jsonArrayStrings(array: JsonArray): Array<String> {
    let items = ArrayList<String>()
    var index: Int64 = 0
    while (index < array.size()) {
        match (array.get(index)) {
            case Some(value) =>
                match (value.kind()) {
                    case JsString => items.add(value.asString().getValue())
                    case _ => items.add(value.toString())
                }
            case None => ()
        }
        index += 1
    }
    return items.toArray()
}

public func containsAny(text: String, candidates: Array<String>): Bool {
    for (candidate in candidates) {
        if (text.contains(candidate)) {
            return true
        }
    }
    return false
}

public func shellQuote(text: String): String {
    return "'${text.replace("'", "'\"'\"'")}'"
}
