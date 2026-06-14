package cangjiecoder.httpx

import std.collection.*
import stdx.encoding.json.*
import cangjiecoder.common.*

/**
 * 完整 assistant 消息解析（非流式）
 *
 * 与 `extractAssistantText` 的区别：本函数返回 (content, toolCalls) 元组，
 * 支持工具调用场景当模型选择调用工具时，content 通常为空，toolCalls 非空
 */

public func extractAssistantMessage(jsonText: String): (String, Array<ToolCall>, String) {
    let jv = JsonValue.fromStr(jsonText)
    let obj = jv.asObject()
    if (let Some(err) <- obj.get("error")) {
        throw HttpException("服务返回错误: ${err.toString()}")
    }
    let choices = obj["choices"].asArray()
    if (choices.size() == 0) {
        throw HttpException("响应缺少 choices 字段: ${jsonText}")
    }
    let first = choices[0].asObject()
    let message = first["message"].asObject()

    var content = ""
    if (let Some(c) <- message.get("content")) {
        content = flattenContent(c)
    }
    var reasoningContent = ""
    if (let Some(r) <- message.get("reasoning_content")) {
        reasoningContent = flattenContent(r)
    }

    let toolCalls = ArrayList<ToolCall>()
    if (let Some(tcs) <- message.get("tool_calls")) {
        match (tcs.kind()) {
            case JsArray =>
                let arr = tcs.asArray()
                for (i in 0..arr.size()) {
                    match (parseToolCall(arr[i])) {
                        case Some(tc) => toolCalls.add(tc)
                        case None => ()
                    }
                }
            case _ => ()
        }
    }

    // 当 content 为空但有 reasoning_content 时，不再将推理内容覆盖到 content，
    // 避免内部推理过程泄露到 history 的 assistant content 中被重复发送
    // 推理内容通过 reasoningContent 字段独立传递，由上层按需展示
    if (content.isEmpty() && toolCalls.size == 0 && reasoningContent.isEmpty()) {
        throw HttpException("响应既无文本也无 tool_calls: ${truncateForError(jsonText)}")
    }
    return (content, toolCalls.toArray(), reasoningContent)
}

func parseToolCall(v: JsonValue): ?ToolCall {
    match (v.kind()) {
        case JsObject => ()
        case _ => return None
    }
    let obj = v.asObject()
    var id = ""
    if (let Some(value) <- obj.get("id")) {
        match (value.kind()) {
            case JsString => id = value.asString().getValue()
            case _ => ()
        }
    }
    let fn = match (obj.get("function")) {
        case Some(value) => value
        case None => return None
    }
    match (fn.kind()) {
        case JsObject => ()
        case _ => return None
    }
    let fnObj = fn.asObject()
    var name = ""
    var args = "{}"
    if (let Some(value) <- fnObj.get("name")) {
        match (value.kind()) {
            case JsString => name = value.asString().getValue()
            case _ => ()
        }
    }
    if (let Some(value) <- fnObj.get("arguments")) {
        match (value.kind()) {
            case JsString => args = value.asString().getValue()
            case JsObject => args = value.asObject().toString()
            case _ => ()
        }
    }
    if (name.isEmpty()) {
        return None
    }
    return Some(ToolCall(id, name, args))
}

// 错误消息中截断响应体，避免泄露敏感数据或产生过长错误字符串
let ERROR_RESPONSE_TRUNCATE: Int64 = 500

func truncateForError(s: String): String {
    return truncateWithEllipsis(s, ERROR_RESPONSE_TRUNCATE)
}
