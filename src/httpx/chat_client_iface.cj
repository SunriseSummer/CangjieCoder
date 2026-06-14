package cangjiecoder.httpx

/**
 * Chat 客户端的最小接口：抽象出 agent loop 真正依赖的能力
 *
 * 引入接口的目的：
 *  - 允许在端到端测试中注入 mock client（无需真正发起 HTTP 请求）
 *  - 让 `AgentLoop` 等更上层的逻辑只依赖接口、不耦合到具体的 HTTP 实现
 */

public interface IChatClient {
    /**
     * 非流式发送，返回完整 assistant 消息
     * 三元组：(content, toolCalls, reasoningContent)
     * reasoningContent 为思考模型（如 kimi-k2.6）的内部推理过程，
     * 必须在后续请求中随 assistant 消息一起回传，否则 API 返回 400
     */
    func sendForMessage(req: ChatRequest): (String, Array<ToolCall>, String)
}
