package cangjiecoder.httpx

import stdx.encoding.json.*
import cangjiecoder.common.*

/**
 * 响应解析工具，兼容 OpenAI Chat Completions 与 SSE 流式协议
 */

/** 从非流式 `chat/completions` 响应中提取 assistant 文本 */
public func extractAssistantText(jsonText: String): String {
    let jv = JsonValue.fromStr(jsonText)
    let obj = jv.asObject()
    if (let Some(err) <- obj.get("error")) {
        throw HttpException("服务返回错误: ${err.toString()}")
    }
    let choices = obj["choices"].asArray()
    if (choices.size() == 0) {
        throw HttpException("响应缺少 choices 字段: ${truncateWithEllipsis(jsonText, 500)}")
    }
    let first = choices[0].asObject()
    let message = first["message"].asObject()
    if (let Some(c) <- message.get("content")) {
        let text = flattenContent(c)
        if (!text.isEmpty()) {
            return text
        }
    }
    if (let Some(r) <- message.get("reasoning_content")) {
        let text = flattenContent(r)
        if (!text.isEmpty()) {
            return text
        }
    }
    throw HttpException("响应无可读文本: ${truncateWithEllipsis(jsonText, 500)}")
}

/**
 * 解析单帧 SSE `data:` JSON，返回 (contentDelta, finished, reasoningDelta)
 */
public func parseStreamChunk(jsonText: String): (String, Bool, String) {
    let jv = JsonValue.fromStr(jsonText)
    let obj = jv.asObject()
    if (let Some(err) <- obj.get("error")) {
        throw HttpException("流式响应错误: ${err.toString()}")
    }
    let choices = match (obj.get("choices")) {
        case Some(v) => v.asArray()
        case None => return ("", false, "")
    }
    if (choices.size() == 0) {
        return ("", false, "")
    }
    let first = choices[0].asObject()
    var finished = false
    if (let Some(v) <- first.get("finish_reason")) {
        match (v.kind()) {
            case JsString => finished = !v.asString().getValue().isEmpty()
            case _ => ()
        }
    }
    var content = ""
    var reasoning = ""
    if (let Some(d) <- first.get("delta")) {
        let delta = d.asObject()
        if (let Some(c) <- delta.get("content")) {
            content = flattenContent(c)
        }
        if (let Some(r) <- delta.get("reasoning_content")) {
            reasoning = flattenContent(r)
        }
    }
    return (content, finished, reasoning)
}

/** 将 string 或 [{text:"..."}] 数组的 content 字段扁平化为字符串 */
public func flattenContent(v: JsonValue): String {
    match (v.kind()) {
        case JsString => return v.asString().getValue()
        case JsNull => return ""
        case JsArray => return flattenArray(v.asArray())
        case _ => return ""
    }
}

func flattenArray(arr: JsonArray): String {
    let sb = StringBuilder()
    for (i in 0..arr.size()) {
        let item = arr[i]
        match (item.kind()) {
            case JsString => sb.append(item.asString().getValue())
            case JsObject => appendObjectText(sb, item.asObject())
            case _ => ()
        }
    }
    return sb.toString()
}

func appendObjectText(sb: StringBuilder, obj: JsonObject): Unit {
    if (let Some(t) <- obj.get("text")) {
        match (t.kind()) {
            case JsString => sb.append(t.asString().getValue())
            case _ => ()
        }
        return
    }
    if (let Some(c) <- obj.get("content")) {
        match (c.kind()) {
            case JsString => sb.append(c.asString().getValue())
            case _ => ()
        }
    }
}

public class HttpException <: Exception {
    public init(msg: String) {
        super(msg)
    }
}
