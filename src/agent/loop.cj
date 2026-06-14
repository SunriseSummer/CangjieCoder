package cangjiecoder.agent

import std.collection.*
import cangjiecoder.httpx.*
import cangjiecoder.tools.*

/**
 * 多轮 Agent Loop（OpenAI 兼容 tool calling）
 *
 * 算法：
 *   1. 用户输入消息追加到 history，
 *   2. 调用模型 sendForMessage，得到 (content, toolCalls)，
 *   3. 若 toolCalls 非空：
 *        - 把 assistant 消息（含 tool_calls）追加到 history，
 *        - 逐个执行工具，把 role:tool 消息追加，
 *        - 继续第 2 步，
 *   4. 若无 toolCalls：assistant 消息追加，返回 content，
 *   5. 超过 maxIterations 强制停止并提示
 */
public class AgentLoop {
    public let client: IChatClient
    public let registry: ToolRegistry
    public let approver: Approver
    public var endpoint: String
    public var apiKey: String
    public var model: String
    public var systemPrompt: String
    public let history: ArrayList<ChatMessage>
    public var maxIterations: Int64

    public init(
        client: IChatClient,
        registry: ToolRegistry,
        approver: Approver,
        endpoint: String,
        apiKey: String,
        model: String,
        systemPrompt: String,
        maxIterations!: Int64 = defaultMaxIterations()
    ) {
        this.client = client
        this.registry = registry
        this.approver = approver
        this.endpoint = endpoint
        this.apiKey = apiKey
        this.model = model
        this.systemPrompt = systemPrompt
        this.history = ArrayList<ChatMessage>()
        this.maxIterations = maxIterations
    }

    public func clearHistory(): Unit {
        this.history.clear()
    }

    public func run(userInput: String): String {
        this.history.add(ChatMessage.user(userInput))
        let tools = collectToolSpecs(this.registry)
        var iter = 0
        while (iter < this.maxIterations) {
            iter++
            let msgs = buildRequestMessages(this.systemPrompt, this.history)
            let req = ChatRequest(this.endpoint, this.apiKey, this.model, msgs, stream: false, tools: tools)
            let (content, toolCalls, reasoningContent) = try {
                sendWithRetry(this.client, req)
            } catch (e: Exception) {
                rollbackToLastUser(this.history)
                throw e
            }
            if (toolCalls.size == 0) {
                let displayContent = if (content.isEmpty()) {
                    reasoningContent
                } else {
                    content
                }
                this.history.add(ChatMessage.assistant(content))
                return displayContent
            }
            announceAssistant(content, toolCalls)
            this.history.add(ChatMessage.assistantWithTools(content, toolCalls, reasoningContent: reasoningContent))
            appendToolResponses(this.registry, this.approver, this.history, toolCalls)
        }
        let msg = "已达到 ${this.maxIterations} 轮迭代上限，如需继续请发送新指令。"
        this.history.add(ChatMessage.assistant(msg))
        return msg
    }
}
