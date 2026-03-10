// JSON 提取：从模型输出中定位有效的 JSON 对象
package cangjiecoderagent.planner

import std.collection.*
import stdx.encoding.json.*

// 使用花括号深度计数从文本中提取 JSON 对象，
// 正确处理嵌套对象、字符串内的花括号和转义序列。
// 优先返回包含 steps/summary 字段的规划对象。
public func extractJsonObjectText(text: String): String {
    let codeFence = "```"
    let fencedStart = match (text.indexOf(codeFence)) {
        case Some(value) => value
        case None => -1
    }
    if (fencedStart >= 0) {
        let fencedEnd = match (text.indexOf(codeFence, fencedStart + codeFence.size)) {
            case Some(value) => value
            case None => -1
        }
        if (fencedEnd > fencedStart) {
            let fencedBody = text[fencedStart + codeFence.size..fencedEnd]
            let nested = extractJsonObjectText(fencedBody)
            if (!nested.isEmpty()) {
                return nested
            }
        }
    }

    let candidates = ArrayList<String>()
    var scanIndex: Int64 = 0
    while (scanIndex < text.size) {
        if (text[scanIndex..scanIndex + 1] != "{") {
            scanIndex += 1
            continue
        }
        let objStart = scanIndex
        var depth: Int64 = 0
        var inString = false
        var escaped = false
        var pos = objStart
        while (pos < text.size) {
            let ch = text[pos..pos + 1]
            if (escaped) {
                escaped = false
                pos += 1
                continue
            }
            if (ch == "\\") {
                escaped = true
                pos += 1
                continue
            }
            if (ch == "\"") {
                inString = !inString
                pos += 1
                continue
            }
            if (!inString) {
                if (ch == "{") {
                    depth += 1
                } else if (ch == "}") {
                    depth -= 1
                    if (depth == 0) {
                        candidates.add(text[objStart..pos + 1])
                        break
                    }
                }
            }
            pos += 1
        }
        scanIndex = objStart + 1
    }

    // 逐个尝试解析候选 JSON，优先返回包含 steps/summary 字段的规划对象
    for (candidate in candidates) {
        try {
            let root = JsonValue.fromStr(candidate).asObject()
            let hasSteps = match (root.get("steps")) {
                case Some(_) => true
                case None => false
            }
            let hasSummary = match (root.get("summary")) {
                case Some(_) => true
                case None => false
            }
            if (hasSteps || hasSummary) {
                return candidate
            }
        } catch (e: Exception) {
            continue
        }
    }
    // 没有 steps/summary 字段时退化到第一个合法 JSON 对象
    for (candidate in candidates) {
        try {
            JsonValue.fromStr(candidate)
            return candidate
        } catch (e: Exception) {
            continue
        }
    }
    return ""
}
