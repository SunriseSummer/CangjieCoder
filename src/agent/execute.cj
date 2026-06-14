package cangjiecoder.agent

import cangjiecoder.common.*
import cangjiecoder.tools.*
import cangjiecoder.httpx.*

/**
 * 单次工具执行：包含审批与异常包装
 *
 * 若工具不存在 / 审批失败，仍返回一个 ToolResult，
 * agent loop 会把它作为 role:tool 的消息回写，便于模型从错误中恢复
 */

public func executeOne(reg: ToolRegistry, approver: Approver, tc: ToolCall): ToolResult {
    let tool = match (reg.get(tc.name)) {
        case Some(t) => t
        case None =>
            let msg = "未知工具: ${tc.name}（请仅使用已注册工具）"
            println("")
            println("[tool-result]")
            println(msg)
            return ToolResult.err(msg)
    }
    let (allowed, switchAuto) = approver.confirm(tc.name, tc.argumentsJson, tool.approval)
    if (switchAuto) {
        approver.policy = Auto
        println("")
        println("[审批]")
        println("已切换为 auto 模式")
    }
    if (!allowed) {
        let msg = "用户拒绝执行工具 ${tc.name}"
        println("")
        println("[tool-result]")
        println(msg)
        return ToolResult.err(msg)
    }
    let result = try {
        tool.execute(tc.argumentsJson)
    } catch (e: Exception) {
        ToolResult.err("工具内部异常: ${e.message}")
    }
    // 显示代码使用独立 try-catch 保护：即使 println 或截断抛异常，
    // 也不影响工具结果正常回写到 history
    let prefix = if (result.isError) { "[tool-error]" } else { "[tool-result]" }
    try {
        println("")
        println(prefix)
        println("${tc.name}: ${summarizeResult(result.content, 240)}")
    } catch (_: Exception) {
        println("")
        println(prefix)
        println("${tc.name}: (显示截断异常，结果已正常返回)")
    }
    return result
}

func summarizeResult(s: String, max: Int64): String {
    let oneLine = s.replace("\n", " ⏎ ")
    if (oneLine.size <= max) {
        return oneLine
    }
    return truncateUtf8(oneLine, max) + "..."
}
