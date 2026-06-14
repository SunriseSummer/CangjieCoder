package cangjiecoder.tools

import std.collection.*
import cangjiecoder.skillset.*

/**
 * 创建包含全部内建工具的默认注册中心
 *
 * 工具顺序遵循「读 → 检索 → 编辑 → 执行 → 任务规划 → Skills」的认知次序，
 * 便于模型按需选择
 */

public func defaultRegistry(todoStore: TodoStore): ToolRegistry {
    return defaultRegistry(todoStore, FileJournal(), ArrayList<SkillSummary>())
}

public func defaultRegistry(todoStore: TodoStore, journal: FileJournal): ToolRegistry {
    return defaultRegistry(todoStore, journal, ArrayList<SkillSummary>())
}

public func defaultRegistry(todoStore: TodoStore, journal: FileJournal,
                             skillSummaries: ArrayList<SkillSummary>): ToolRegistry {
    let reg = ToolRegistry()
    reg.add(ReadFileTool())
    reg.add(ListDirTool())
    reg.add(GlobTool())
    reg.add(GrepTool())
    reg.add(EditFileTool(journal))
    reg.add(WriteFileTool(journal))
    reg.add(RunBashTool())
    reg.add(TodoWriteTool(todoStore))
    reg.add(TodoReadTool(todoStore))
    if (skillSummaries.size > 0) {
        reg.add(UseSkillTool(skillSummaries))
    }
    return reg
}
