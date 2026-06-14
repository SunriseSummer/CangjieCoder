package cangjiecoder.commands

import cangjiecoder.agent.*

/**
 * Agent 模式相关命令：/mode、/approve、/tools、/todo
 */

public func handleMode(arg: String, ctx: Context): CommandResult {
    let trimmed = arg.trimAscii().toAsciiLower()
    if (trimmed.isEmpty()) {
        println("当前模式: ${modeName(ctx.mode)}")
        println("可选: chat（纯聊天，流式）/ agent（Coding Agent，可调用工具）")
        return Continue
    }
    match (trimmed) {
        case "chat" =>
            ctx.mode = Chat
            println("已切换到 chat 模式（流式聊天，不调用工具）。")
        case "agent" =>
            ctx.mode = Agent
            println("已切换到 agent 模式（Coding Agent，可读写文件 / 执行命令）。")
        case _ =>
            eprintln("未知模式: ${trimmed}（仅支持 chat / agent）")
    }
    return Continue
}

public func handleApprove(arg: String, ctx: Context): CommandResult {
    let trimmed = arg.trimAscii()
    if (trimmed.isEmpty()) {
        println("当前审批策略: ${approvalPolicyName(ctx.approver.policy)}")
        println("可选: auto（全部自动放行）/ default（敏感工具询问）/ readonly（拒绝敏感工具）")
        return Continue
    }
    match (parseApprovalPolicy(trimmed)) {
        case Some(p) =>
            ctx.approver.policy = p
            println("审批策略已设为: ${approvalPolicyName(p)}")
        case None =>
            eprintln("未知策略: ${trimmed}")
    }
    return Continue
}

public func handleTools(_: String, ctx: Context): CommandResult {
    let tools = ctx.registry.all()
    println("")
    println("  已注册工具（${tools.size} 个）：")
    println("")
    for (i in 0..tools.size) {
        let tool = tools[i]
        let level = match (tool.approval) {
            case Safe => "safe"
            case Sensitive => "sensitive"
        }
        println("  ${(i + 1).toString().padStart(2)}. ${tool.name.padEnd(16)} [${level.padEnd(9)}]  ${tool.description}")
    }
    println("")
    return Continue
}

public func handleTodo(_: String, ctx: Context): CommandResult {
    println(ctx.todoStore.render())
    return Continue
}
