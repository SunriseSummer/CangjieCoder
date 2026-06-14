package cangjiecoder.commands

import std.env.*
import cangjiecoder.skillset.*
import cangjiecoder.config.*
import cangjiecoder.agent.*

/**
 * 系统提示与 Skills 相关命令：/system、/skills
 *
 * 修改时同时刷新 chat session 与 agent loop 的 systemPrompt，
 * 并清空两侧历史以避免「旧上下文 + 新系统提示」的语义偏移
 */

public func handleSystem(arg: String, ctx: Context): CommandResult {
    let trimmed = arg.trimAscii()
    if (trimmed.isEmpty()) {
        let view = if (ctx.baseSystemPrompt.isEmpty()) {
            "<空>"
        } else {
            ctx.baseSystemPrompt
        }
        println("当前基础 system prompt: ${view}")
        return Continue
    }
    ctx.baseSystemPrompt = trimmed
    ctx.config.systemPrompt = trimmed
    refreshPrompts(ctx)
    saveConfig(ctx.config)
    println("已更新 system prompt，并清空对话历史。")
    return Continue
}

public func handleSkills(_: String, ctx: Context): CommandResult {
    let cwd = getWorkingDirectory()
    let summaries = discoverSkillSummaries(cwd)
    if (summaries.size == 0) {
        println("未在 ${cwd.toString()}/.agents/skills 下发现 Skill。")
    } else {
        println("发现 ${summaries.size} 个 Skill：")
        for (i in 0..summaries.size) {
            let s = summaries[i]
            println("  ${i + 1}. ${s.name}  -  ${s.description}")
        }
    }
    refreshPrompts(ctx)
    println("已重新构建系统提示并清空对话历史。")
    return Continue
}

/**
 * 重新根据 baseSystemPrompt + Skills 构造 chat / agent 的 system prompt
 * agent 模式下还会拼接项目上下文与工具说明
 *
 * 与 bootstrap 一致，采用按需加载模式：仅读取 name + description，
 * 由 AI 通过 use_skill 工具按需加载完整内容
 */
public func refreshPrompts(ctx: Context): Unit {
    let cwd = getWorkingDirectory()
    let summaries = discoverSkillSummaries(cwd)
    let extra = renderSkillCatalog(summaries)
    let base = ctx.baseSystemPrompt
    let chatPrompt = if (extra.isEmpty()) {
        base
    } else if (base.isEmpty()) {
        extra
    } else {
        base + "\n\n" + extra
    }
    ctx.session.systemPrompt = chatPrompt
    ctx.session.clearHistory()

    ctx.agent.systemPrompt = buildAgentSystemPrompt(chatPrompt, ctx.registry)
    ctx.agent.clearHistory()
}
