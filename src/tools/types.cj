package cangjiecoder.tools

import std.fs.*
import cangjiecoder.httpx.*

/**
 * 工具调用核心抽象
 *
 * 设计原则：
 *  - `Tool` 是无状态的（除全局 TODO 等少量例外），便于并行调用与测试，
 *  - 工具参数为 JSON 对象（与 OpenAI function calling 一致），
 *  - 工具结果由 `ToolResult` 包装，区分成功 / 失败，便于上层判断是否回退
 */
public class ToolResult {
    public let content: String
    public let isError: Bool

    public init(content: String, isError!: Bool = false) {
        this.content = content
        this.isError = isError
    }

    public static func ok(content: String): ToolResult {
        return ToolResult(content, isError: false)
    }

    public static func err(content: String): ToolResult {
        return ToolResult(content, isError: true)
    }
}

public enum ApprovalLevel {
    /** 总是放行（read 类工具） */
    | Safe
    /** 需要询问用户（write/edit/run_bash 类） */
    | Sensitive
}

public interface Tool {
    prop name: String
    prop description: String
    /** JSON Schema 字符串，描述 `parameters` 字段 */
    prop parametersSchemaJson: String
    prop approval: ApprovalLevel
    /** 实际执行`argumentsJson` 为模型返回的 arguments 原始文本（可能为空） */
    func execute(argumentsJson: String): ToolResult
}

public func toToolSpec(t: Tool): ToolSpec {
    return ToolSpec(t.name, t.description, t.parametersSchemaJson)
}

/** 安全读取文件字节，失败返回 None（用于替代 try { File.readFrom } catch） */
public func tryReadBytes(path: Path): ?Array<Byte> {
    try {
        Some(File.readFrom(path))
    } catch (_: Exception) {
        None
    }
}

/** 安全 UTF-8 解码，失败返回 None（用于替代 try { String.fromUtf8 } catch） */
public func tryDecodeUtf8(bytes: Array<Byte>): ?String {
    try {
        Some(String.fromUtf8(bytes))
    } catch (_: Exception) {
        None
    }
}

/** 安全读取文件并解码为 UTF-8 文本，失败返回 None */
public func tryReadFileText(path: Path): ?String {
    let bytes = tryReadBytes(path) ?? return None
    return tryDecodeUtf8(bytes)
}
