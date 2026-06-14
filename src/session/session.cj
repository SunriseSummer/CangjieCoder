package cangjiecoder.session

import std.collection.*
import cangjiecoder.httpx.*

/**
 * 单轮聊天会话：维护历史消息，发送请求时附带可选的系统提示
 */

public class ChatSession {
    public var endpoint: String
    public var apiKey: String
    public var model: String
    public var systemPrompt: String
    public var stream: Bool
    public let history: ArrayList<ChatMessage>
    let client: ChatClient

    public init(endpoint: String, apiKey: String, model: String, systemPrompt!: String = "",
                stream!: Bool = true, client!: ChatClient = ChatClient()) {
        this.endpoint = endpoint
        this.apiKey = apiKey
        this.model = model
        this.systemPrompt = systemPrompt
        this.stream = stream
        this.history = ArrayList<ChatMessage>()
        this.client = client
    }

    public func clearHistory(): Unit {
        this.history.clear()
    }

    public func send(userText: String, onChunk: ?StreamCallback): String {
        let msgs = ArrayList<ChatMessage>()
        if (!this.systemPrompt.trimAscii().isEmpty()) {
            msgs.add(ChatMessage.system(this.systemPrompt))
        }
        for (msg in this.history) {
            msgs.add(msg)
        }
        msgs.add(ChatMessage.user(userText))
        let req = ChatRequest(this.endpoint, this.apiKey, this.model, msgs, stream: this.stream)
        let reply = this.client.send(req, onChunk)
        this.history.add(ChatMessage.user(userText))
        this.history.add(ChatMessage.assistant(reply))
        return reply
    }

    /** 直接暴露 client，供 agent loop 在 session 之外驱动多轮对话 */
    public func getClient(): ChatClient {
        return this.client
    }
}
