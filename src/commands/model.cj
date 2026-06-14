package cangjiecoder.commands

import cangjiecoder.config.*
import std.convert.*

/**
 * `/model` — 查看或切换当前服务商下的模型
 *
 * 用法：
 *   /model               显示当前模型并列出可选模型
 *   /model 2             按序号切换
 *   /model deepseek-v4-pro  按模型 ID 切换
 */

public func handleModel(arg: String, ctx: Context): CommandResult {
    let trimmed = arg.trimAscii()
    let models = ctx.provider.models
    if (trimmed.isEmpty()) {
        listModels(ctx)
        return Continue
    }
    var target: ?Int64 = None
    if (let Some(idx) <- Int64.tryParse(trimmed)) {
        if (idx >= 1 && idx <= models.size) {
            target = Some(idx - 1)
        }
    }
    var picked: ?Int64 = target
    if (picked.isNone()) {
        for (i in 0..models.size) {
            if (models[i].id == trimmed) {
                picked = Some(i)
                break
            }
        }
    }
    match (picked) {
        case Some(i) =>
            ctx.model = models[i]
            ctx.session.model = ctx.model.id
            ctx.agent.model = ctx.model.id
            ctx.config.currentModel = ctx.model.id
            saveConfig(ctx.config)
            println("已切换到 ${ctx.model.displayName} (${ctx.model.id})")
        case None =>
            eprintln("未知模型: ${trimmed}")
            listModels(ctx)
    }
    return Continue
}

func listModels(ctx: Context): Unit {
    println("服务商: ${ctx.provider.displayName} (${ctx.provider.id})")
    println("当前模型: ${ctx.model.displayName} (${ctx.model.id})")
    println("可选模型:")
    let models = ctx.provider.models
    for (i in 0..models.size) {
        let model = models[i]
        let mark = if (model.id == ctx.model.id) { " *" } else { "  " }
        println("  ${i + 1}.${mark} ${model.id}  -  ${model.displayName}")
    }
}
