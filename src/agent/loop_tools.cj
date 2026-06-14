package cangjiecoder.agent

import std.collection.*
import cangjiecoder.common.*
import cangjiecoder.httpx.*
import cangjiecoder.tools.*

let ANNOUNCE_TRUNCATE_LIMIT: Int64 = 200

func collectToolSpecs(reg: ToolRegistry): Array<ToolSpec> {
    let specs = ArrayList<ToolSpec>()
    for (tool in reg.all()) {
        specs.add(toToolSpec(tool))
    }
    return specs.toArray()
}

func announceAssistant(content: String, toolCalls: Array<ToolCall>): Unit {
    if (!content.trimAscii().isEmpty()) {
        println("")
        println("[assistant]")
        println(content.trimAscii())
    }
    for (tc in toolCalls) {
        println("")
        println("[tool-call]")
        println("${tc.name}  ${truncateWithEllipsis(tc.argumentsJson, ANNOUNCE_TRUNCATE_LIMIT)}")
    }
}

/**
 * 为每个 tool_call 写入一条 role:tool 响应
 *
 * 即使工具执行异常，也补齐错误响应以保持下一轮请求协议有效
 */
func appendToolResponses(
    registry: ToolRegistry,
    approver: Approver,
    history: ArrayList<ChatMessage>,
    toolCalls: Array<ToolCall>
): Unit {
    for (tc in toolCalls) {
        let result = try {
            executeOne(registry, approver, tc)
        } catch (e: Exception) {
            eprintln("[tool-fatal] ${tc.name}: ${e.message}")
            ToolResult.err("工具执行异常: ${e.message}")
        }
        history.add(ChatMessage.tool(tc.id, result.content))
    }
}
