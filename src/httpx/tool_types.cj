package cangjiecoder.httpx

/**
 * Tool calling 相关数据结构（OpenAI 兼容格式）
 *
 *  - `ToolCall`：assistant 消息中携带的工具调用条目
 *  - `ToolSpec`：发送给模型的工具规范（name + description + parameters schema）
 */

public class ToolCall {
    public let id: String
    public let name: String
    /** 工具实参的 JSON 文本（OpenAI 协议中为字符串） */
    public let argumentsJson: String

    public init(id: String, name: String, argumentsJson: String) {
        this.id = id
        this.name = name
        this.argumentsJson = argumentsJson
    }
}

public class ToolSpec {
    public let name: String
    public let description: String
    /** JSON Schema 对象的字符串表示（必须是顶层 object） */
    public let parametersSchemaJson: String

    public init(name: String, description: String, parametersSchemaJson: String) {
        this.name = name
        this.description = description
        this.parametersSchemaJson = parametersSchemaJson
    }
}
