package cangjiecoder.httpx

import std.collection.*
import stdx.encoding.json.*

/**
 * 发送给模型的请求负载（OpenAI Chat Completions 兼容）
 *
 * 支持：
 *  - 多消息上下文 messages
 *  - 流式 / 非流式
 *  - 工具调用 tools + tool_choice="auto"
 *  - 温度、max_tokens
 *
 * 注意：当请求中携带 tools 时，建议关闭 stream，
 *      多数服务商对流式 tool_call 增量的支持差异较大
 */

public class ChatRequest {
    public let endpoint: String
    public let apiKey: String
    public let model: String
    public let messages: ArrayList<ChatMessage>
    public var stream: Bool
    public var temperature: ?Float64
    public var maxTokens: ?Int64
    public var tools: Array<ToolSpec>

    public init(
        endpoint: String,
        apiKey: String,
        model: String,
        messages: ArrayList<ChatMessage>,
        stream!: Bool = true,
        temperature!: ?Float64 = None,
        maxTokens!: ?Int64 = None,
        tools!: Array<ToolSpec> = Array<ToolSpec>()
    ) {
        this.endpoint = endpoint
        this.apiKey = apiKey
        this.model = model
        this.messages = messages
        this.stream = stream
        this.temperature = temperature
        this.maxTokens = maxTokens
        this.tools = tools
    }

    public func toJsonBody(): String {
        let root = JsonObject()
        root.put("model", JsonString(this.model))
        root.put("stream", JsonBool(this.stream))
        match (this.temperature) {
            case Some(t) => root.put("temperature", JsonFloat(t))
            case None => ()
        }
        match (this.maxTokens) {
            case Some(n) => root.put("max_tokens", JsonInt(n))
            case None => ()
        }
        root.put("messages", buildMessagesJson(this.messages))
        if (this.tools.size > 0) {
            root.put("tools", buildToolsJson(this.tools))
            root.put("tool_choice", JsonString("auto"))
        }
        return root.toString()
    }
}

func buildMessagesJson(messages: ArrayList<ChatMessage>): JsonArray {
    let arr = JsonArray()
    for (msg in messages) {
        let mo = JsonObject()
        mo.put("role", JsonString(msg.role))
        mo.put("content", JsonString(msg.content))
        if (!msg.toolCallId.isEmpty()) {
            mo.put("tool_call_id", JsonString(msg.toolCallId))
        }
        if (msg.toolCalls.size > 0) {
            mo.put("tool_calls", buildToolCallsJson(msg.toolCalls))
        }
        // 思考模型（如 kimi-k2.6）要求 assistant 消息携带 reasoning_content，
        // 若缺失 API 会返回 400 "reasoning_content is missing"
        if (!msg.reasoningContent.isEmpty()) {
            mo.put("reasoning_content", JsonString(msg.reasoningContent))
        }
        arr.add(mo)
    }
    return arr
}

func buildToolCallsJson(toolCalls: Array<ToolCall>): JsonArray {
    let arr = JsonArray()
    for (tc in toolCalls) {
        let obj = JsonObject()
        obj.put("id", JsonString(tc.id))
        obj.put("type", JsonString("function"))
        let fn = JsonObject()
        fn.put("name", JsonString(tc.name))
        fn.put("arguments", JsonString(tc.argumentsJson))
        obj.put("function", fn)
        arr.add(obj)
    }
    return arr
}

func buildToolsJson(tools: Array<ToolSpec>): JsonArray {
    let arr = JsonArray()
    for (tool in tools) {
        let obj = JsonObject()
        obj.put("type", JsonString("function"))
        let fn = JsonObject()
        fn.put("name", JsonString(tool.name))
        fn.put("description", JsonString(tool.description))
        // 工具的 parameters schema 通常用 Cangjie 的 ##"""..."""## 多行 raw
        // string 字面量书写该字面量真正以 `##"` / `"##` 为定界符，所以
        // 内容里会带有冗余的前后 `""`、以及多余的换行 / 空白，stdx 的
        // JsonValue.fromStr 对前导字符严格，必须先归一化到「以 `{` 或 `[`
        // 开始、以 `}` 或 `]` 结束」的纯 JSON 文本再喂入，否则整轮 agent
        // 请求会因 "Unexpected character: '{'" 而失败（已通过 e2etest 复现）
        fn.put("parameters", JsonValue.fromStr(sanitizeSchemaJson(tool.parametersSchemaJson)))
        obj.put("function", fn)
        arr.add(obj)
    }
    return arr
}

/**
 * 把 raw-string 形式的 JSON Schema 归一化为标准 JSON：剥掉前后 `\n` / 空格 /
 * 多余的 `"`，直到第一个 `{` 或 `[`（前者）与最后一个 `}` 或 `]`（后者）
 * 暴露为 public 便于回归测试
 */
// JSON 结构定界字符的字节值
let BYTE_JSON_LBRACE: UInt8 = 123    // '{'
let BYTE_JSON_RBRACE: UInt8 = 125    // '}'
let BYTE_JSON_LBRACKET: UInt8 = 91   // '['
let BYTE_JSON_RBRACKET: UInt8 = 93   // ']'

public func sanitizeSchemaJson(s: String): String {
    let bytes = s.toArray()
    var start: Int64 = 0
    while (start < bytes.size) {
        let ch = bytes[start]
        if (ch == BYTE_JSON_LBRACE || ch == BYTE_JSON_LBRACKET) {
            break
        }
        start++
    }
    var end: Int64 = bytes.size - 1
    while (end >= start) {
        let ch = bytes[end]
        if (ch == BYTE_JSON_RBRACE || ch == BYTE_JSON_RBRACKET) {
            break
        }
        end--
    }
    if (end < start) {
        return "{}"
    }
    return s[start..end + 1]
}
