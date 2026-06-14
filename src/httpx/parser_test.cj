package cangjiecoder.httpx

import std.unittest.*
import std.unittest.testmacro.*

@Test
class ExtractAssistantTextTests {
    @TestCase
    func extractsBasicContent() {
        let r = ##"{"choices":[{"message":{"content":"hello"}}]}"##
        @Expect(extractAssistantText(r), "hello")
    }

    @TestCase
    func fallsBackToReasoningContent() {
        let r = ##"{"choices":[{"message":{"content":"","reasoning_content":"thought"}}]}"##
        @Expect(extractAssistantText(r), "thought")
    }

    @TestCase
    func throwsOnError() {
        let r = ##"{"error":{"message":"boom"}}"##
        @ExpectThrows[HttpException](extractAssistantText(r))
    }

    @TestCase
    func throwsOnEmptyChoices() {
        let r = ##"{"choices":[]}"##
        @ExpectThrows[HttpException](extractAssistantText(r))
    }

    @TestCase
    func throwsWhenNeitherContentNorReasoning() {
        let r = ##"{"choices":[{"message":{}}]}"##
        @ExpectThrows[HttpException](extractAssistantText(r))
    }
}

@Test
class ExtractAssistantMessageTests {
    @TestCase
    func contentOnly() {
        let r = ##"{"choices":[{"message":{"content":"done"}}]}"##
        let (c, calls, _) = extractAssistantMessage(r)
        @Expect(c, "done")
        @Expect(calls.size, 0)
    }

    @TestCase
    func toolCallsWithStringArguments() {
        let r = ##"{"choices":[{"message":{"content":"","tool_calls":[
          {"id":"c1","type":"function","function":{"name":"read_file","arguments":"{\"path\":\"a.txt\"}"}}
        ]}}]}"##
        let (c, calls, _) = extractAssistantMessage(r)
        @Expect(c, "")
        @Expect(calls.size, 1)
        @Expect(calls[0].id, "c1")
        @Expect(calls[0].name, "read_file")
        @Expect(calls[0].argumentsJson.contains("a.txt"), true)
    }

    @TestCase
    func toolCallsWithObjectArguments() {
        // 部分服务商把 arguments 直接以对象返回（非标准但常见）
        let r = ##"{"choices":[{"message":{"content":"","tool_calls":[
          {"id":"c2","type":"function","function":{"name":"list_dir","arguments":{"path":"."}}}
        ]}}]}"##
        let (_, calls, _) = extractAssistantMessage(r)
        @Expect(calls.size, 1)
        @Expect(calls[0].name, "list_dir")
        @Expect(calls[0].argumentsJson.contains("path"), true)
    }

    @TestCase
    func multipleToolCalls() {
        let r = ##"{"choices":[{"message":{"content":"","tool_calls":[
          {"id":"c1","type":"function","function":{"name":"a","arguments":"{}"}},
          {"id":"c2","type":"function","function":{"name":"b","arguments":"{}"}}
        ]}}]}"##
        let (_, calls, _) = extractAssistantMessage(r)
        @Expect(calls.size, 2)
        @Expect(calls[0].name, "a")
        @Expect(calls[1].name, "b")
    }

    @TestCase
    func skipsToolCallsWithoutName() {
        // 缺 name 的条目直接丢弃
        let r = ##"{"choices":[{"message":{"content":"x","tool_calls":[
          {"id":"c1","type":"function","function":{"arguments":"{}"}}
        ]}}]}"##
        let (c, calls, _) = extractAssistantMessage(r)
        @Expect(c, "x")
        @Expect(calls.size, 0)
    }

    @TestCase
    func throwsOnError() {
        @ExpectThrows[HttpException](extractAssistantMessage(##"{"error":{"x":1}}"##))
    }

    @TestCase
    func throwsWhenBothEmpty() {
        // 既无 content 也无 tool_calls
        let r = ##"{"choices":[{"message":{}}]}"##
        @ExpectThrows[HttpException](extractAssistantMessage(r))
    }

    @TestCase
    func capturesReasoningContent() {
        // 思考模型（如 kimi-k2.6）会在 reasoning_content 中返回推理过程
        let r = ##"{"choices":[{"message":{"content":"answer","reasoning_content":"I am thinking..."}}]}"##
        let (c, calls, rc) = extractAssistantMessage(r)
        @Expect(c, "answer")
        @Expect(calls.size, 0)
        @Expect(rc, "I am thinking...")
    }

    @TestCase
    func reasoningContentWithToolCalls() {
        // 思考模型调用工具时也携带 reasoning_content
        // content 保持原始值（空），不再将 reasoning_content 复制到 content，
        // 避免推理内容泄露到 history 的 assistant content 中被重复发送
        let r = ##"{"choices":[{"message":{"content":"","reasoning_content":"need to list files","tool_calls":[
          {"id":"c1","type":"function","function":{"name":"list_dir","arguments":"{}"}}
        ]}}]}"##
        let (c, calls, rc) = extractAssistantMessage(r)
        @Expect(c, "")  // content 保持原始空值
        @Expect(calls.size, 1)
        @Expect(calls[0].name, "list_dir")
        @Expect(rc, "need to list files")
    }

    @TestCase
    func reasoningOnlyNoToolCallsDoesNotThrow() {
        // 仅有 reasoning_content、无 content 也无 tool_calls 时，
        // 修复后不再抛异常（reasoning_content 本身即可作为有效响应）
        let r = ##"{"choices":[{"message":{"content":"","reasoning_content":"thinking hard..."}}]}"##
        let (c, calls, rc) = extractAssistantMessage(r)
        @Expect(c, "")
        @Expect(calls.size, 0)
        @Expect(rc, "thinking hard...")
    }

    @TestCase
    func emptyContentEmptyReasoningNoToolCallsThrows() {
        // content 为空、reasoning_content 为空、无 tool_calls → 仍应抛异常
        let r = ##"{"choices":[{"message":{"content":"","reasoning_content":""}}]}"##
        @ExpectThrows[HttpException](extractAssistantMessage(r))
    }
}

@Test
class TruncateForErrorTests {
    @TestCase
    func shortStringUnchanged() {
        let s = "short error"
        @Expect(truncateForError(s), s)
    }

    @TestCase
    func longStringTruncated() {
        let sb = StringBuilder()
        for (_ in 0..600) { sb.append("x") }
        let long = sb.toString()
        let result = truncateForError(long)
        @Expect(result.size < long.size, true)
    }
}

@Test
class ParseStreamChunkTests {
    @TestCase
    func contentDelta() {
        let r = ##"{"choices":[{"delta":{"content":"hel"}}]}"##
        let (c, finished, reasoning) = parseStreamChunk(r)
        @Expect(c, "hel")
        @Expect(finished, false)
        @Expect(reasoning, "")
    }

    @TestCase
    func reasoningDelta() {
        let r = ##"{"choices":[{"delta":{"reasoning_content":"think"}}]}"##
        let (_, _, reasoning) = parseStreamChunk(r)
        @Expect(reasoning, "think")
    }

    @TestCase
    func finishReasonMarksFinished() {
        let r = ##"{"choices":[{"delta":{},"finish_reason":"stop"}]}"##
        let (_, finished, _) = parseStreamChunk(r)
        @Expect(finished, true)
    }

    @TestCase
    func emptyFinishReasonNotFinished() {
        let r = ##"{"choices":[{"delta":{},"finish_reason":""}]}"##
        let (_, finished, _) = parseStreamChunk(r)
        @Expect(finished, false)
    }

    @TestCase
    func noChoicesGivesEmpty() {
        let r = "{}"
        let (c, finished, reasoning) = parseStreamChunk(r)
        @Expect(c, "")
        @Expect(finished, false)
        @Expect(reasoning, "")
    }

    @TestCase
    func throwsOnErrorPayload() {
        @ExpectThrows[HttpException](parseStreamChunk(##"{"error":{"m":"x"}}"##))
    }
}
