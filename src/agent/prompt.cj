package cangjiecoder.agent

import std.env.*
import std.fs.*
import cangjiecoder.common.*
import cangjiecoder.tools.*

/**
 * 构造 Agent 模式下的系统提示
 *
 * 结构（自上而下，越靠前权重越高）：
 *  1. 角色 + 行为准则
 *  2. 工具使用指南
 *  3. 当前工作目录 + 顶层文件树概览
 *  4. AGENTS.md / README.md 项目说明（如有）
 *  5. 用户基础 system_prompt（可空）
 */

public let AGENT_PERSONA: String =
    "你是 Cangjie Coder，一位严谨的 AI 软件工程师。你具备以下能力：\n" +
    "  - 通过工具读写文件、检索代码、执行命令；\n" +
    "  - 维护 TODO 任务清单，按计划逐步推进；\n" +
    "  - 在不确定时主动检索与验证，不臆造事实。\n" +
    "工作准则：\n" +
    "  1. 在动手前先理解目标和上下文：必要时使用 list_dir/glob_search/grep_search/read_file 探索；\n" +
    "  2. 对多步骤任务，优先用 todo_write 列出计划，并在每步完成后更新状态；\n" +
    "  3. 修改文件优先用 edit_file（精确替换），仅在新建文件时用 write_file；\n" +
    "  4. 编辑前要先 read_file 核对当前内容；\n" +
    "  5. 执行命令前评估风险；只运行项目已有的 lint/build/test，不引入新工具；\n" +
    "  6. 最终回答用简洁的自然语言总结改动与验证结果，不要重复粘贴大段代码；\n" +
    "  7. 仅在所有任务确认完成后停止调用工具。"

public let AGENT_TOOL_GUIDE: String =
    "工具调用必须使用 OpenAI function calling 协议；" +
    "参数为合法 JSON，路径使用相对路径。"

public func buildAgentSystemPrompt(baseSystemPrompt: String, _: ToolRegistry): String {
    let sb = StringBuilder()
    sb.append(AGENT_PERSONA)
    sb.append("\n\n")
    sb.append(AGENT_TOOL_GUIDE)
    sb.append("\n\n## 项目上下文\n")
    sb.append("工作目录: ${getWorkingDirectory().toString()}\n\n")
    sb.append(buildProjectOverview())
    let docs = readProjectDocs()
    if (!docs.isEmpty()) {
        sb.append("\n\n## 项目说明\n")
        sb.append(docs)
    }
    if (!baseSystemPrompt.trimAscii().isEmpty()) {
        sb.append("\n\n## 附加指令\n")
        sb.append(baseSystemPrompt)
    }
    return sb.toString()
}

// 项目概览最大顶层条目数
let MAX_PROJECT_ENTRIES: Int64 = 30
// 项目文档截断限制（字节）
let DOC_TRUNCATE_LIMIT: Int64 = 4000

func buildProjectOverview(): String {
    let cwd = getWorkingDirectory()
    let sb = StringBuilder()
    sb.append("顶层条目（最多 ${MAX_PROJECT_ENTRIES} 条）：\n")
    try {
        let entries = Directory.readFrom(cwd)
        var count: Int64 = 0
        for (entry in entries) {
            if (count >= MAX_PROJECT_ENTRIES) {
                sb.append("  ...\n")
                break
            }
            if (isNoiseEntry(entry.name)) {
                continue
            }
            let suffix = if (entry.isDirectory()) { "/" } else { "" }
            sb.append("  ${entry.name}${suffix}\n")
            count++
        }
    } catch (_: Exception) {
        sb.append("  <无法读取工作目录>\n")
    }
    return sb.toString()
}

func readProjectDocs(): String {
    let candidates = ["AGENTS.md", "agents.md", "README.md", "readme.md"]
    for (name in candidates) {
        let docPath = Path(name)
        if (exists(docPath)) {
            try {
                let text = String.fromUtf8(File.readFrom(docPath))
                return truncateDoc(text, DOC_TRUNCATE_LIMIT)
            } catch (_: Exception) { () }
        }
    }
    return ""
}

func truncateDoc(s: String, max: Int64): String {
    return truncateWithEllipsis(s, max, suffix: "\n<...文档已截断，使用 read_file 查看完整内容...>")
}
