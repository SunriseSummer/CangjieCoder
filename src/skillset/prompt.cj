package cangjiecoder.skillset

import std.collection.*

/**
 * 将一组 Skill 渲染为 system prompt 增量片段
 *
 * 设计原则：
 *  - 仅放置 Skill 名称、文件路径与正文，便于模型按需引用，
 *  - 若 Skill 数量为 0，返回空串以避免污染上下文
 */

public let SKILLS_HEADER: String =
    "以下是当前项目目录 `.agents/skills/` 下提供的领域 Skills，" +
    "请在回答涉及对应主题时优先参考其内容："

public func renderSkillsPrompt(skills: ArrayList<Skill>): String {
    if (skills.size == 0) {
        return ""
    }
    let sb = StringBuilder()
    sb.append(SKILLS_HEADER)
    sb.append("\n\n")
    for (i in 0..skills.size) {
        let skill = skills[i]
        sb.append("## Skill: ")
        sb.append(skill.name)
        sb.append("\n描述：")
        sb.append(skill.description)
        sb.append("\n来源：")
        sb.append(skill.path)
        sb.append("\n\n")
        sb.append(skill.content.trimAscii())
        sb.append("\n\n")
    }
    return sb.toString()
}

/**
 * 按需加载模式下的 Skills 目录渲染：
 * 仅列出 name + description，提示模型使用 use_skill 工具按需加载
 */

public let SKILLS_CATALOG_HEADER: String =
    "当前项目目录 `.agents/skills/` 下提供了以下领域 Skills（按需加载）。\n" +
    "需要参考某个 Skill 时，请调用 `use_skill` 工具加载其完整内容。\n" +
    "可用 Skills："

public func renderSkillCatalog(summaries: ArrayList<SkillSummary>): String {
    if (summaries.size == 0) {
        return ""
    }
    let sb = StringBuilder()
    sb.append(SKILLS_CATALOG_HEADER)
    sb.append("\n\n")
    for (i in 0..summaries.size) {
        let summary = summaries[i]
        sb.append("- **")
        sb.append(summary.name)
        sb.append("**：")
        sb.append(summary.description)
        sb.append("\n")
    }
    return sb.toString()
}
