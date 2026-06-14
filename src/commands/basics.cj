package cangjiecoder.commands

import cangjiecoder.agent.*

/**
 * 基础命令：/help、/status、/clear、/exit
 */

public func handleHelp(_: String, _: Context): CommandResult {
    println("")
    println("  可用命令：")
    println("")
    println("  /help                            查看帮助")
    println("  /status                          查看当前会话状态")
    println("  /connect [provider]              切换服务商并设置 API Key")
    println("  /model   [id|序号]               查看或切换模型")
    println("  /mode    [chat|agent]            切换交互模式")
    println("  /approve [auto|default|readonly] 设置工具审批策略")
    println("  /tools                           列出已注册的工具")

    println("  /todo                            查看任务清单")
    println("  /diff                            查看文件改动摘要")
    println("  /undo                            回滚最近一次改动")
    println("  /compact [N]                     压缩 Agent 历史")
    println("  /skills                          重新加载项目 Skills")
    println("  /system  [文本]                  查看或修改 system prompt")
    println("  /clear                           清空对话历史")
    println("  /exit                            退出")
    println("")
    return Continue
}

public func handleClear(_: String, ctx: Context): CommandResult {
    ctx.session.clearHistory()
    ctx.agent.clearHistory()
    println("已清空 chat 与 agent 的对话历史。")
    return Continue
}

public func handleStatus(_: String, ctx: Context): CommandResult {
    println("")
    println("  模式        ${modeName(ctx.mode)}")
    println("  服务商      ${ctx.provider.displayName} (${ctx.provider.id})")
    println("  模型        ${ctx.model.displayName} (${ctx.model.id})")
    println("  Endpoint    ${ctx.session.endpoint}")
    println("  审批策略    ${approvalPolicyName(ctx.approver.policy)}")
    println("  Chat 历史   ${ctx.session.history.size / 2} 轮")
    println("  Agent 历史  ${ctx.agent.history.size} 条")
    println("  注册工具    ${ctx.registry.names().size} 个")
    println("  文件改动    ${ctx.journal.size()} 次")
    println("")
    return Continue
}

public func handleExit(_: String, _: Context): CommandResult {
    println("再见！")
    return Exit
}
