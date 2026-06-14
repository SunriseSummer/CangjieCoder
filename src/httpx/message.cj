package cangjiecoder.httpx

/**
 * 聊天消息：兼容 OpenAI Chat Completions 的 `messages` 结构
 *
 * 角色及其字段约定：
 *   - role = "system"    ：仅 content
 *   - role = "user"      ：仅 content
 *   - role = "assistant" ：content 可空，可携带 toolCalls
 *   - role = "tool"      ：必须设置 toolCallId 与 content
 */

public class ChatMessage {
    public let role: String
    public let content: String
    public let toolCalls: Array<ToolCall>
    public let toolCallId: String
    public let reasoningContent: String

    public init(
        role: String,
        content: String,
        toolCalls!: Array<ToolCall> = Array<ToolCall>(),
        toolCallId!: String = "",
        reasoningContent!: String = ""
    ) {
        this.role = role
        this.content = content
        this.toolCalls = toolCalls
        this.toolCallId = toolCallId
        this.reasoningContent = reasoningContent
    }

    public static func user(content: String): ChatMessage {
        return ChatMessage("user", content)
    }

    public static func system(content: String): ChatMessage {
        return ChatMessage("system", content)
    }

    public static func assistant(content: String): ChatMessage {
        return ChatMessage("assistant", content)
    }

    public static func assistantWithTools(content: String, toolCalls: Array<ToolCall>,
                                          reasoningContent!: String = ""): ChatMessage {
        return ChatMessage("assistant", content, toolCalls: toolCalls,
                          reasoningContent: reasoningContent)
    }

    public static func tool(toolCallId: String, content: String): ChatMessage {
        return ChatMessage("tool", content, toolCallId: toolCallId)
    }
}
