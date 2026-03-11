// 提示词构建：为 LLM 生成规划和重规划的提示词
package cangjiecoderagent.planner

import std.collection.*
import cangjiecoderagent.common.*

// 规划提示词中共用的探索性补充规则
const PLAN_EXPLORE_RULE: String = "- use workspace.list_files or workspace.read_file to explore the workspace when needed"

// 将完整工作区快照压缩为紧凑摘要，只保留文件计数、关键文件和顶层目录结构，
// 避免每轮提示词中灌入全量文件列表浪费 token 预算和干扰模型注意力。
public func buildCompactWorkspaceSummary(snapshot: String): String {
    let snapshotRoot = parseJsonObject(snapshot)
    let data = extractStructuredData(snapshotRoot)
    let count = jsonField(data, "count", fallback: "0")
    let files = extractWorkspaceFiles(snapshot)

    let keyFiles = ArrayList<String>()
    for (file in files) {
        if (file.endsWith("cjpm.toml") || file.endsWith("README.md") ||
            file == "src/main.cj" || file.endsWith("/main.cj")) {
            keyFiles.add(file)
        }
    }

    let summary = ArrayList<String>()
    summary.add("Workspace: ${count} files total")
    if (!keyFiles.isEmpty()) {
        summary.add("Key files: ${String.join(keyFiles.toArray(), delimiter: ", ")}")
    }

    let dirs = HashSet<String>()
    for (file in files) {
        match (file.indexOf("/")) {
            case Some(slashIndex) =>
                dirs.add(file[0..slashIndex])
            case None => ()
        }
    }
    if (!dirs.isEmpty()) {
        let dirList = ArrayList<String>()
        for (d in dirs) {
            dirList.add(d)
        }
        summary.add("Top-level dirs: ${String.join(dirList.toArray(), delimiter: ", ")}")
    }

    let sourceFiles = ArrayList<String>()
    for (file in files) {
        if (file.endsWith(".cj") && !file.contains("_test.cj")) {
            sourceFiles.add(file)
        }
    }
    if (!sourceFiles.isEmpty()) {
        summary.add("Source files: ${String.join(sourceFiles.toArray(), delimiter: ", ")}")
    }

    return String.join(summary.toArray(), delimiter: "\n")
}

public func buildPlanPrompt(context: AgentPlanningContext): String {
    let workspaceSummary = buildCompactWorkspaceSummary(context.workspaceSnapshot)
    return """
You are the single-agent planner for CangjieCoder.

User request:
${context.userPrompt}

Available MCP tools (JSON):
${context.toolsJson}

Workspace overview:
${workspaceSummary}

Built-in example projects (JSON):
${context.exampleProjectsJson}

Return strict JSON only with this shape:
{
  "summary": "one sentence",
  "steps": [
    {
      "tool": "<tool_name_from_list>",
      "arguments": {},
      "reason": "why"
    }
  ]
}

Rules:
- choose at most ${MAX_PLAN_STEPS} steps
- use only tool names from the provided tool list
- if the user asks for a new project, use project.bootstrap with a matching project_id (json_parser, todo_list, calculator)
- prefer reading configuration/docs or analyzing code before destructive changes
- include workspace.run_build / workspace.run_test when they are clearly needed
- do not wrap the JSON in markdown
${PLAN_EXPLORE_RULE}
"""
}

public func buildReplanPrompt(userPrompt: String,
                       previousPlans: Array<AgentPlan>,
                       executions: Array<ToolExecution>,
                       context: AgentPlanningContext): String {
    let planLines = ArrayList<String>()
    for (plan in previousPlans) {
        planLines.add("- ${plan.summary}")
        for (step in plan.steps) {
            planLines.add("  - ${step.tool}: ${step.reason}")
        }
    }

    let executionLines = ArrayList<String>()
    for (execution in executions) {
        executionLines.add("- tool=${execution.tool}")
        executionLines.add("  ok=${execution.ok}")
        executionLines.add("  summary=${execution.summary}")
        if (!execution.preview.trimAscii().isEmpty()) {
            executionLines.add("  preview=${execution.preview}")
        }
    }

    let workspaceSummary = buildCompactWorkspaceSummary(context.workspaceSnapshot)
    return """
You are continuing a CangjieCoder agent run using a reflect-plan-act-review loop.

Original user request:
${userPrompt}

Previous plan summaries:
${String.join(planLines.toArray(), delimiter: "\n")}

Observed tool executions:
${String.join(executionLines.toArray(), delimiter: "\n")}

Current workspace overview:
${workspaceSummary}

Available MCP tools (JSON):
${context.toolsJson}

Return strict JSON only with the same schema as before.

Rules:
- if the task is already complete, return {"summary":"done","steps":[]}
- prefer targeted next steps instead of repeating already executed steps
- if a previous step failed, focus on diagnosis, repair, or verification
- choose at most ${MAX_PLAN_STEPS} steps
- use only tool names from the provided tool list
- do not wrap the JSON in markdown
${PLAN_EXPLORE_RULE}
"""
}
