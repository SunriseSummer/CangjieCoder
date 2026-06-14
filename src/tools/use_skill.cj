package cangjiecoder.tools

import std.collection.*
import cangjiecoder.skillset.*

/**
 * `use_skill` 工具：按需加载 Skills 的完整内容
 *
 * 初始化时系统提示只包含 Skills 目录（name + description），
 * 模型根据任务需要决定加载哪些 Skill 的完整文档
 * 这避免了将所有 Skills 内容一次性注入系统提示，
 * 节省 token 开销并降低上下文噪声
 *
 * 安全级别：Safe（只读操作，读取 .agents/skills 下的文档）
 */
public class UseSkillTool <: Tool {
    let summaries: ArrayList<SkillSummary>

    public init(summaries: ArrayList<SkillSummary>) {
        this.summaries = summaries
    }

    public prop name: String {
        get() {
            return "use_skill"
        }
    }

    public prop description: String {
        get() {
            return "加载指定 Skill 的完整文档内容。" +
                "传入 Skill 名称（如 'cangjie-std'），返回该 Skill 的完整指引文档。" +
                "用于在需要特定领域知识时按需获取详细信息。"
        }
    }

    public prop parametersSchemaJson: String {
        get() {
            return ##"""
{
  "type": "object",
  "properties": {
    "name": {"type": "string", "description": "要加载的 Skill 名称，必须是系统提示中列出的可用 Skill 之一"}
  },
  "required": ["name"]
}
"""##
        }
    }

    public prop approval: ApprovalLevel {
        get() {
            return Safe
        }
    }

    public func execute(argumentsJson: String): ToolResult {
        let args = parseArgs(argumentsJson)
        let skillName = requireString(args, "name") ?? return ToolResult.err("缺少必填参数 name")

        // 在已发现的 summaries 中查找匹配的 Skill
        var dirPath = ""
        for (summary in this.summaries) {
            if (summary.name == skillName) {
                dirPath = summary.dirPath
                break
            }
        }
        if (dirPath.isEmpty()) {
            let available = StringBuilder()
            for (summary in this.summaries) {
                if (available.size > 0) {
                    available.append(", ")
                }
                available.append(summary.name)
            }
            return ToolResult.err("未找到名为 '${skillName}' 的 Skill。可用 Skills: ${available.toString()}")
        }

        match (loadSkillContent(dirPath)) {
            case Some((_, body)) => return ToolResult.ok(body)
            case None => return ToolResult.err("加载 Skill '${skillName}' 失败：SKILL.md 文件不存在或格式无效")
        }
    }
}
