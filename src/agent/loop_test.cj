package cangjiecoder.agent

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cangjiecoder.httpx.*
import cangjiecoder.tools.*

/**
 * `isTransient` 行为：
 *  - 命中已知瞬时错误关键字时返回 true（UTF-8 / 连接重置 / EOF / 读写超时）
 *  - 永久性错误（HTTP 4xx、TLS 校验失败、鉴权失败）返回 false，会被外抛
 */
@Test
class TransientErrorTests {

    @TestCase
    func detectsInvalidUtf8(): Unit {
        @Expect(isTransient(HttpException("Invalid utf8 byte sequence.")), true)
    }

    @TestCase
    func detectsConnectionReset(): Unit {
        @Expect(isTransient(HttpException("connection reset by peer")), true)
        @Expect(isTransient(HttpException("Connection reset")), true)
    }

    @TestCase
    func detectsEofAndTimeouts(): Unit {
        @Expect(isTransient(HttpException("unexpected EOF")), true)
        @Expect(isTransient(HttpException("read timeout")), true)
        @Expect(isTransient(HttpException("write timeout")), true)
    }

    @TestCase
    func rejectsPermanentErrors(): Unit {
        @Expect(isTransient(HttpException("HTTP 401: invalid api key")), false)
        @Expect(isTransient(HttpException("HTTP 429: rate limit")), false)
        @Expect(isTransient(HttpException("TLS handshake failed: unknown CA")), false)
        @Expect(isTransient(HttpException("HTTP 500: internal server error")), false)
    }
}

/**
 * `sendWithRetry` 在 transient 错误后会自动重试最多 3 次（指数退避 1/2/4 秒）
 */
class FakeFlakyClient <: IChatClient {
    var calls: Int64 = 0
    let failCount: Int64    // 前 failCount 次调用抛瞬时错误
    let reply: (String, Array<ToolCall>, String)

    init(failCount!: Int64) {
        this.failCount = failCount
        this.reply = ("ok", Array<ToolCall>(), "")
    }

    public func send(_: ChatRequest, _: ?StreamCallback): String {
        return ""
    }

    public func sendForMessage(_: ChatRequest): (String, Array<ToolCall>, String) {
        this.calls++
        if (this.calls <= this.failCount) {
            throw HttpException("Invalid utf8 byte sequence.")
        }
        return this.reply
    }
}

class FakePermanentFailClient <: IChatClient {
    var calls: Int64 = 0

    public func send(_: ChatRequest, _: ?StreamCallback): String {
        return ""
    }

    public func sendForMessage(_: ChatRequest): (String, Array<ToolCall>, String) {
        this.calls++
        throw HttpException("HTTP 401: invalid api key")
    }
}

@Test
class SendWithRetryTests {

    @TestCase
    func retriesOnceOnTransient(): Unit {
        let client = FakeFlakyClient(failCount: 1)
        let req = ChatRequest("http://x", "k", "m",
                              ArrayList<ChatMessage>(), stream: false)
        let (content, _, _) = sendWithRetry(client, req)
        @Expect(content, "ok")
        @Expect(client.calls, 2)
    }

    @TestCase
    func retriesMultipleTimesOnTransient(): Unit {
        let client = FakeFlakyClient(failCount: 3)
        let req = ChatRequest("http://x", "k", "m",
                              ArrayList<ChatMessage>(), stream: false)
        let (content, _, _) = sendWithRetry(client, req)
        @Expect(content, "ok")
        @Expect(client.calls, 4)  // 3 failures + 1 success
    }

    @TestCase
    func doesNotRetryWhenFirstSucceeds(): Unit {
        let client = FakeFlakyClient(failCount: 0)
        let req = ChatRequest("http://x", "k", "m",
                              ArrayList<ChatMessage>(), stream: false)
        let _ = sendWithRetry(client, req)
        @Expect(client.calls, 1)
    }

    @TestCase
    func permanentErrorNotRetried(): Unit {
        let client = FakePermanentFailClient()
        let req = ChatRequest("http://x", "k", "m",
                              ArrayList<ChatMessage>(), stream: false)
        var threw = false
        try {
            let _ = sendWithRetry(client, req)
        } catch (_: Exception) {
            threw = true
        }
        @Expect(threw, true)
        @Expect(client.calls, 1)  // no retry on permanent error
    }
}

/**
 * `rollbackToLastUser` 确保 history 在异常后恢复到有效状态
 */
@Test
class RollbackTests {

    @TestCase
    func rollbackRemovesUserAndSubsequent(): Unit {
        let history = ArrayList<ChatMessage>()
        history.add(ChatMessage.system("sys"))
        history.add(ChatMessage.user("q1"))
        history.add(ChatMessage.assistant("a1"))
        history.add(ChatMessage.user("q2"))                   // <- last user
        history.add(ChatMessage.assistantWithTools("", [ToolCall("tc1", "write_file", "{}")]))
        history.add(ChatMessage.tool("tc1", "ok"))
        // 共 6 条，rollback 应移除索引 3..5（user("q2") 及其后续）
        rollbackToLastUser(history)
        @Expect(history.size, 3)
        @Expect(history[2].role, "assistant")
    }

    @TestCase
    func rollbackOnEmptyHistory(): Unit {
        let history = ArrayList<ChatMessage>()
        rollbackToLastUser(history)
        @Expect(history.size, 0)
    }

    @TestCase
    func rollbackOnlyUser(): Unit {
        let history = ArrayList<ChatMessage>()
        history.add(ChatMessage.user("q1"))
        rollbackToLastUser(history)
        @Expect(history.size, 0)
    }

    @TestCase
    func agentLoopRollbackOnFailure(): Unit {
        // 模拟：第一次 sendForMessage 成功返回 tool_calls，
        // 第二次全部失败 → agent loop 应 rollback history
        let client = FakeToolThenFailClient()
        let reg = ToolRegistry()
        reg.add(FakeNoopTool())
        let approver = Approver(Auto)
        let loop = AgentLoop(client, reg, approver, "http://x", "k", "m", "")
        var threw = false
        try {
            let _ = loop.run("hello")
        } catch (_: Exception) {
            threw = true
        }
        @Expect(threw, true)
        // history 应为空（user("hello") 及后续全被回滚）
        @Expect(loop.history.size, 0)
    }
}

/**
 * 第一次 sendForMessage 返回一个 tool_call，
 * 第二次开始持续抛 transient 错误（超出重试上限）
 */
class FakeToolThenFailClient <: IChatClient {
    var calls: Int64 = 0

    public func send(_: ChatRequest, _: ?StreamCallback): String {
        return ""
    }

    public func sendForMessage(_: ChatRequest): (String, Array<ToolCall>, String) {
        this.calls++
        if (this.calls == 1) {
            return ("", [ToolCall("t1", "noop", "{}")], "")
        }
        throw HttpException("Invalid utf8 byte sequence.")
    }
}

class FakeNoopTool <: Tool {
    public prop name: String { get() { return "noop" } }
    public prop description: String { get() { return "no-op" } }
    public prop parametersSchemaJson: String { get() { return ##"{"type":"object","properties":{}}"## } }
    public prop approval: ApprovalLevel { get() { return Safe } }
    public func execute(_: String): ToolResult {
        return ToolResult.ok("done")
    }
}
