package cangjiecoderagent

import std.collection.*
import stdx.encoding.json.*

func isMutatingTool(tool: String): Bool {
    return tool == "workspace.replace_text" || tool == "cangjie.edit_ast_node" || tool == "project.bootstrap_json_parser"
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
            if (tool == "project.bootstrap_json_parser") {
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
        results.add(PlannedToolCall("workspace.run_build", arguments, "Automatically validate a mutating step with cjpm build."))
    }
    if (requiresValidation && !hasTest && containsTool(allowedTools, "workspace.run_test")) {
        let arguments = JsonObject()
        arguments.put("path", JsonString(validationPath))
        results.add(PlannedToolCall("workspace.run_test", arguments, "Automatically validate a mutating step with cjpm test."))
    }
    return results.toArray()
}

func formatExecution(result: JsonObject, tool: String): ToolExecution {
    let ok = jsonField(result, "ok", fallback: "false") == "true"
    let summary = jsonField(result, "summary")
    let data = extractStructuredData(result)
    return ToolExecution(tool, ok, summary, shortPreview(data.toString(), maxLines: MAX_TRANSCRIPT_LINES))
}

func buildFinalPrompt(userPrompt: String, plan: AgentPlan, executions: Array<ToolExecution>): String {
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
