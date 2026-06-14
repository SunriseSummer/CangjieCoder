package cangjiecoder.commands

import std.collection.*
import std.convert.*
import std.sort.*
import cangjiecoder.httpx.*

/**
 * `/compact` 命令：手动压缩 agent 对话历史
 *
 * 灵感来自 Anthropic Claude Code 的 `/compact`：在长任务中，对话历史
 * 会撑爆上下文窗口压缩策略是「保留首条用户指令 + 摘要中间过程 + 保留
 * 最近 N 轮原文」
 *
 * 当前实现采用纯本地算法（不发起额外的 LLM 调用，确定性强、零成本）：
 *  - 找到 history 中所有 role == "user" 的消息，保留**首条**（初始任务），
 *  - 统计中间被丢弃的 assistant / tool / user 消息数目，以及调用过的
 *    工具名（去重），
 *  - 把上述统计写成一条「[历史已压缩]」的合成 user 消息插入到首条之后，
 *  - 保留最近 `tailKeep` 条原始消息（默认 6 条，命令参数可覆盖），同时
 *    确保压缩后历史在 OpenAI 协议上是合法的：每条 assistant(toolCalls)
 *    必须紧跟它的 tool 响应若 tail 边界落在了 (assistant tool_calls,
 *    tool, tool) 块的中间，自动向前回溯到块开始处
 */

// 历史压缩时默认保留的末尾消息条数
let DEFAULT_TAIL_KEEP: Int64 = 6

public func handleCompact(arg: String, ctx: Context): CommandResult {
    let trimmed = arg.trimAscii()
    var tailKeep: Int64 = DEFAULT_TAIL_KEEP
    if (!trimmed.isEmpty()) {
        match (Int64.tryParse(trimmed)) {
            case Some(parsed) where parsed > 0 => tailKeep = parsed
            case _ =>
                eprintln("无效参数: ${trimmed}（应为正整数）")
                return Continue
        }
    }

    let history = ctx.agent.history
    let before = history.size
    if (before <= tailKeep + 1) {
        println("对话历史仅 ${before} 条，无需压缩（阈值 ${tailKeep + 1}）")
        return Continue
    }

    // 1) 找首个 user 消息
    var firstUserIdx: Int64 = -1
    for (i in 0..history.size) {
        if (history[i].role == "user") {
            firstUserIdx = i
            break
        }
    }
    if (firstUserIdx < 0) {
        println("未找到任何 user 消息，无法压缩。")
        return Continue
    }

    // 2) 计算 tail 起点（向前对齐到 tool_calls 块边界）
    var tailStart = history.size - tailKeep
    if (tailStart <= firstUserIdx + 1) {
        println("待压缩范围过小，未执行。")
        return Continue
    }
    tailStart = alignToBlockBoundary(history, tailStart)
    if (tailStart <= firstUserIdx + 1) {
        println("对齐后无中间内容可压缩。")
        return Continue
    }

    // 3) 统计被压缩段的信息
    var droppedAssistant: Int64 = 0
    var droppedTool: Int64 = 0
    var droppedUser: Int64 = 0
    let toolNames = HashMap<String, Int64>()
    for (i in firstUserIdx + 1..tailStart) {
        let msg = history[i]
        match (msg.role) {
            case "assistant" =>
                droppedAssistant++
                for (tc in msg.toolCalls) {
                    toolNames[tc.name] = match (toolNames.get(tc.name)) {
                        case Some(count) => count + 1
                        case None => 1
                    }
                }
            case "tool" => droppedTool++
            case "user" => droppedUser++
            case _ => ()
        }
    }
    let summary = renderCompactSummary(droppedAssistant, droppedTool, droppedUser, toolNames)

    // 4) 重建 history：[0..=firstUserIdx] + 合成 user(摘要) + [tailStart..)
    let rebuilt = ArrayList<ChatMessage>()
    for (i in 0..firstUserIdx + 1) {
        rebuilt.add(history[i])
    }
    rebuilt.add(ChatMessage.user(summary))
    for (i in tailStart..history.size) {
        rebuilt.add(history[i])
    }
    history.clear()
    for (msg in rebuilt) {
        history.add(msg)
    }

    println("历史已压缩：${before} 条 → ${history.size} 条；摘要插入第 ${firstUserIdx + 2} 位")
    return Continue
}

/**
 * 把 idx 向前对齐：若 h[idx] 是 role="tool"，说明它属于上一条
 * assistant(toolCalls) 的响应，必须连同 assistant 一起保留，所以
 * 把 idx 退到那条 assistant 的位置
 *
 * 暴露为 public 以便单元测试覆盖（无副作用、纯函数）
 */
public func alignToBlockBoundary(h: ArrayList<ChatMessage>, idx: Int64): Int64 {
    var current = idx
    while (current > 0 && h[current].role == "tool") {
        current--
    }
    return current
}

public func renderCompactSummary(
    droppedAssistant: Int64,
    droppedTool: Int64,
    droppedUser: Int64,
    toolNames: HashMap<String, Int64>
): String {
    let sb = StringBuilder()
    sb.append("[历史已压缩] 此处省略了对话中间 ")
    sb.append("${droppedUser} 条 user / ${droppedAssistant} 条 assistant / ")
    sb.append("${droppedTool} 条 tool 消息。")
    if (toolNames.size > 0) {
        sb.append(" 期间调用过的工具：")
        // 排序以确保输出稳定、可复现
        let sortedNames = ArrayList<String>()
        for ((name, _) in toolNames) {
            sortedNames.add(name)
        }
        sort(sortedNames)
        var first = true
        for (name in sortedNames) {
            if (!first) { sb.append("、") }
            sb.append("${name}×${toolNames[name]}")
            first = false
        }
        sb.append("。")
    }
    sb.append(" 后续请基于最近的对话继续。")
    return sb.toString()
}
