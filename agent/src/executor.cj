package cangjiecoderagent

import std.collection.*
import stdx.encoding.json.*
import cangjiecoderagent.common.*
import cangjiecoderagent.planner.*

func isMutatingTool(tool: String): Bool {
    // 这里集中维护“会改变工作区状态”的工具集合，
    // runner 与自动补充验证步骤都依赖这个判定。
    return tool == "workspace.replace_text" ||
        tool == "workspace.create_file" ||
        tool == "cangjie.edit_ast_node" ||
        tool == "project.bootstrap_json_parser" ||
        tool == "project.bootstrap"
}

func appendValidationSteps(steps: Array<PlannedToolCall>, allowedTools!: Array<String> = ["workspace.run_build", "workspace.run_test"]): Array<PlannedToolCall> {
    let results = ArrayList<PlannedToolCall>()
    var requiresValidation = false
    var hasBuild = false
    var hasTest = false
    var validationPath = "."
    for (step in steps) {
        let tool = step.tool.trimAscii()
        results.add(step)
        if (isMutatingTool(tool)) {
            requiresValidation = true
            if (tool == "project.bootstrap_json_parser" || tool == "project.bootstrap") {
                // bootstrap 往往生成独立子项目，因此优先对目标目录做构建/测试，
                // 避免错误地在当前目录执行验证。
                let bootstrapPath = jsonField(step.arguments, "path")
                if (!bootstrapPath.trimAscii().isEmpty()) {
                    validationPath = bootstrapPath
                }
            }
        }
        if (tool == "workspace.run_build") {
            hasBuild = true
        }
        if (tool == "workspace.run_test") {
            hasTest = true
        }
    }
    if (requiresValidation && !hasBuild && containsTool(allowedTools, "workspace.run_build")) {
        let arguments = JsonObject()
        arguments.put("path", JsonString(validationPath))
        // 自动补 build，确保任何修改类动作至少经过一次编译验证。
        results.add(PlannedToolCall("workspace.run_build", arguments, "Automatically validate a mutating step with cjpm build."))
    }
    if (requiresValidation && !hasTest && containsTool(allowedTools, "workspace.run_test")) {
        let arguments = JsonObject()
        arguments.put("path", JsonString(validationPath))
        // 自动补 test，优先把“改了但没验证”的风险在同一轮内暴露出来。
        results.add(PlannedToolCall("workspace.run_test", arguments, "Automatically validate a mutating step with cjpm test."))
    }
    return results.toArray()
}

func formatExecution(result: JsonObject, tool: String, arguments: JsonObject): ToolExecution {
    // service 返回的原始 JSON 会在这里收敛成稳定的内部结构，
    // 后续无论是 replanning 还是最终总结都只消费 ToolExecution。
    let ok = jsonField(result, "ok", fallback: "false") == "true"
    let summary = jsonField(result, "summary")
    let data = extractStructuredData(result)
    return ToolExecution(tool, arguments, ok, summary, shortPreview(data.toString(), maxLines: MAX_TRANSCRIPT_LINES))
}

func buildFinalPrompt(userPrompt: String, plan: AgentPlan, executions: Array<ToolExecution>): String {
    // 最终总结提示词只拼接执行事实，不重复塞入过多上下文，
    // 让模型聚焦于产出“做了什么 / 是否成功 / 下一步建议”。
    let lines = ArrayList<String>()
    lines.add("plan-summary=${plan.summary}")
    for (execution in executions) {
        lines.add("tool=${execution.tool}")
        lines.add("ok=${execution.ok}")
        lines.add("summary=${execution.summary}")
        lines.add("preview=${execution.preview}")
        lines.add("")
    }
    return """
The user request was:
${userPrompt}

Planner summary:
${plan.summary}

Tool execution transcript:
${String.join(lines.toArray(), delimiter: "\n")}

Please provide a concise Chinese status report that includes:
1. what was executed
2. whether it succeeded
3. important outputs or failures
4. the next recommended step
"""
}

func buildLocalFinalSummary(plan: AgentPlan, executions: Array<ToolExecution>): String {
    // 当远端 provider 不可用时，仍然返回可读的本地摘要，
    // 保证 agent 至少能稳定输出执行轨迹和后续建议。
    let lines = ArrayList<String>()
    lines.add("模型总结不可用，已退化为本地执行摘要：")
    lines.add("计划摘要：${plan.summary}")
    for (execution in executions) {
        lines.add("- ${execution.tool}: ${if (execution.ok) { "成功" } else { "失败" }} / ${execution.summary}")
        if (!execution.preview.trimAscii().isEmpty()) {
            lines.add("  ${execution.preview}")
        }
    }
    lines.add("建议：如需模型生成更完整的重构/实现说明，请在可访问 Moonshot API 的环境下重新运行。")
    return String.join(lines.toArray(), delimiter: "\n")
}
