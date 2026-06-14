package cangjiecoder.httpx

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import stdx.encoding.json.*

func parseObj(s: String): JsonObject {
    return JsonValue.fromStr(s).asObject()
}

@Test
class ChatRequestSerializationTests {
    @TestCase
    func basicFieldsRoundtrip() {
        let msgs = ArrayList<ChatMessage>()
        msgs.add(ChatMessage.user("hello"))
        let req = ChatRequest("ep", "k", "m1", msgs, stream: false)
        let obj = parseObj(req.toJsonBody())
        @Expect(obj["model"].asString().getValue(), "m1")
        @Expect(obj["stream"].asBool().getValue(), false)
        @Expect(obj["messages"].asArray().size(), 1)
    }

    @TestCase
    func systemAndUserMessagesEncoded() {
        let msgs = ArrayList<ChatMessage>()
        msgs.add(ChatMessage.system("you are X"))
        msgs.add(ChatMessage.user("hi"))
        let req = ChatRequest("e", "k", "m", msgs, stream: true)
        let arr = parseObj(req.toJsonBody())["messages"].asArray()
        @Expect(arr.size(), 2)
        @Expect(arr[0].asObject()["role"].asString().getValue(), "system")
        @Expect(arr[0].asObject()["content"].asString().getValue(), "you are X")
        @Expect(arr[1].asObject()["role"].asString().getValue(), "user")
    }

    @TestCase
    func toolMessageEmitsToolCallId() {
        let msgs = ArrayList<ChatMessage>()
        msgs.add(ChatMessage.tool("call_42", "result content"))
        let req = ChatRequest("e", "k", "m", msgs)
        let obj = parseObj(req.toJsonBody())
        let first = obj["messages"].asArray()[0].asObject()
        @Expect(first["role"].asString().getValue(), "tool")
        @Expect(first["tool_call_id"].asString().getValue(), "call_42")
        @Expect(first["content"].asString().getValue(), "result content")
    }

    @TestCase
    func assistantWithToolCallsEncoded() {
        let calls = [ToolCall("c1", "read_file", "{\"path\":\"a.txt\"}")]
        let msgs = ArrayList<ChatMessage>()
        msgs.add(ChatMessage.assistantWithTools("", calls))
        let req = ChatRequest("e", "k", "m", msgs)
        let obj = parseObj(req.toJsonBody())
        let first = obj["messages"].asArray()[0].asObject()
        let tcs = first["tool_calls"].asArray()
        @Expect(tcs.size(), 1)
        let tc = tcs[0].asObject()
        @Expect(tc["id"].asString().getValue(), "c1")
        @Expect(tc["type"].asString().getValue(), "function")
        let fn = tc["function"].asObject()
        @Expect(fn["name"].asString().getValue(), "read_file")
        @Expect(fn["arguments"].asString().getValue(), "{\"path\":\"a.txt\"}")
    }

    @TestCase
    func toolsAndToolChoiceEmittedWhenPresent() {
        let msgs = ArrayList<ChatMessage>()
        msgs.add(ChatMessage.user("x"))
        let tools = [ToolSpec("read_file", "read a file",
            "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}}}")]
        let req = ChatRequest("e", "k", "m", msgs, stream: false, tools: tools)
        let obj = parseObj(req.toJsonBody())
        @Expect(obj.get("tools").isSome(), true)
        @Expect(obj["tool_choice"].asString().getValue(), "auto")
        let t0 = obj["tools"].asArray()[0].asObject()
        @Expect(t0["type"].asString().getValue(), "function")
        @Expect(t0["function"].asObject()["name"].asString().getValue(), "read_file")
    }

    @TestCase
    func toolsOmittedWhenEmpty() {
        let msgs = ArrayList<ChatMessage>()
        msgs.add(ChatMessage.user("x"))
        let req = ChatRequest("e", "k", "m", msgs)
        let obj = parseObj(req.toJsonBody())
        @Expect(obj.get("tools").isNone(), true)
        @Expect(obj.get("tool_choice").isNone(), true)
    }

    @TestCase
    func toolsParametersJsonWithLeadingNewlineSerializes() {
        // 回归：tools 注入的 parameters schema 经常用多行 raw string，
        // 形如「\n{ ... }\n」stdx 的 JsonValue.fromStr 对前导空白严格，
        // ChatRequest 必须先 sanitize 再解析，否则会在 serialize 期间抛出
        // "Unexpected character: '{'"，导致整个 agent 轮请求失败
        let msgs = ArrayList<ChatMessage>()
        msgs.add(ChatMessage.user("go"))
        let schema = "\n{\n  \"type\": \"object\",\n  \"properties\": {}\n}\n"
        let tools = [ToolSpec("t1", "d1", schema)]
        let req = ChatRequest("e", "k", "m", msgs, stream: false, tools: tools)
        let body = req.toJsonBody()  // 不应抛异常
        let obj = parseObj(body)
        let t0 = obj["tools"].asArray()[0].asObject()
        let params = t0["function"].asObject()["parameters"].asObject()
        @Expect(params["type"].asString().getValue(), "object")
    }

    @TestCase
    func toolsParametersJsonFromCangjieRawString() {
        // 回归：复现 Cangjie 真实工具实现里用的 ##"""..."""## 写法所产生的
        // 字符串，会带有前后的 `""` 和换行sanitizeSchemaJson 必须把它
        // 归一化到合法 JSON否则会产生 e2etest 中观察到的 "Unexpected
        // character: '{'" 故障
        let msgs = ArrayList<ChatMessage>()
        msgs.add(ChatMessage.user("go"))
        let schema = ##"""
{
  "type": "object",
  "properties": {
    "path": {"type": "string"}
  },
  "required": ["path"]
}
"""##
        let tools = [ToolSpec("read_file", "read", schema)]
        let req = ChatRequest("e", "k", "m", msgs, stream: false, tools: tools)
        let body = req.toJsonBody()  // 不应抛异常
        let obj = parseObj(body)
        let params = obj["tools"].asArray()[0].asObject()["function"]
            .asObject()["parameters"].asObject()
        @Expect(params["type"].asString().getValue(), "object")
        @Expect(params["required"].asArray().size(), 1)
    }

    @TestCase
    func sanitizeSchemaStripsLeadingTrailingNoise() {
        // 直接覆盖 sanitize 函数：双引号、空白都应被剥除
        @Expect(sanitizeSchemaJson("\"\"\n{\"a\":1}\n\"\""), "{\"a\":1}")
        @Expect(sanitizeSchemaJson("   [1,2]   "), "[1,2]")
        @Expect(sanitizeSchemaJson("{\"x\":\"y\"}"), "{\"x\":\"y\"}")
        @Expect(sanitizeSchemaJson(""), "{}")
    }

    @TestCase
    func temperatureAndMaxTokensOptional() {
        let msgs = ArrayList<ChatMessage>()
        msgs.add(ChatMessage.user("x"))
        let req1 = ChatRequest("e", "k", "m", msgs)
        let o1 = parseObj(req1.toJsonBody())
        @Expect(o1.get("temperature").isNone(), true)
        @Expect(o1.get("max_tokens").isNone(), true)

        let req2 = ChatRequest("e", "k", "m", msgs,
                               temperature: Some(0.3), maxTokens: Some(512))
        let o2 = parseObj(req2.toJsonBody())
        @Expect(o2.get("temperature").isSome(), true)
        @Expect(o2["max_tokens"].asInt().getValue(), 512)
    }
}

@Test
class ChatMessageTests {
    @TestCase
    func factoryRolesAreCorrect() {
        @Expect(ChatMessage.system("s").role, "system")
        @Expect(ChatMessage.user("u").role, "user")
        @Expect(ChatMessage.assistant("a").role, "assistant")
        @Expect(ChatMessage.tool("id", "r").role, "tool")
    }

    @TestCase
    func toolFactoryStoresCallId() {
        let m = ChatMessage.tool("xyz", "ok")
        @Expect(m.toolCallId, "xyz")
        @Expect(m.toolCalls.size, 0)
    }

    @TestCase
    func assistantWithToolsKeepsBoth() {
        let calls = [ToolCall("c", "n", "{}")]
        let m = ChatMessage.assistantWithTools("hi", calls)
        @Expect(m.role, "assistant")
        @Expect(m.content, "hi")
        @Expect(m.toolCalls.size, 1)
        @Expect(m.toolCalls[0].name, "n")
    }

    @TestCase
    func assistantWithToolsAndReasoningContent() {
        let calls = [ToolCall("c", "n", "{}")]
        let m = ChatMessage.assistantWithTools("hi", calls, reasoningContent: "thinking...")
        @Expect(m.role, "assistant")
        @Expect(m.reasoningContent, "thinking...")
        @Expect(m.toolCalls.size, 1)
    }

    @TestCase
    func reasoningContentSerializedInRequest() {
        // 思考模型要求 reasoning_content 随 assistant 消息回传
        let calls = [ToolCall("c1", "list_dir", "{}")]
        let msgs = ArrayList<ChatMessage>()
        msgs.add(ChatMessage.assistantWithTools("", calls, reasoningContent: "I should list files"))
        msgs.add(ChatMessage.tool("c1", "dir listing"))
        let req = ChatRequest("e", "k", "m", msgs)
        let obj = parseObj(req.toJsonBody())
        let first = obj["messages"].asArray()[0].asObject()
        @Expect(first["reasoning_content"].asString().getValue(), "I should list files")
    }

    @TestCase
    func reasoningContentOmittedWhenEmpty() {
        let msgs = ArrayList<ChatMessage>()
        msgs.add(ChatMessage.assistant("plain"))
        let req = ChatRequest("e", "k", "m", msgs)
        let obj = parseObj(req.toJsonBody())
        let first = obj["messages"].asArray()[0].asObject()
        @Expect(first.get("reasoning_content").isNone(), true)
    }
}
