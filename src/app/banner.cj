package cangjiecoder.app

import cangjiecoder.commands.*
import cangjiecoder.agent.*

/**
 * 欢迎横幅与基础提示
 */

public func printBanner(ctx: Context): Unit {
    let bar = hline(49)
    println("")
    println("  ┌${bar}┐")
    println("  │        Cangjie Coder  ·  AI Coding Agent        │")
    println("  │                   仓颉造智机                    │")
    println("  └${bar}┘")
    println("")
    println("    模式      ${modeName(ctx.mode)}")
    println("    审批策略  ${approvalPolicyName(ctx.approver.policy)}")
    println("    服务商    ${ctx.provider.displayName}")
    println("    模型      ${ctx.model.displayName}")
    println("    工具      ${ctx.registry.names().size} 个已注册")
    println("")
    println("    /help 帮助   ·   /connect 服务商   ·   /model 模型")
    println("")
}

func hline(n: Int64): String {
    var s = ""
    var i = 0
    while (i < n) {
        s += "─"
        i++
    }
    return s
}
