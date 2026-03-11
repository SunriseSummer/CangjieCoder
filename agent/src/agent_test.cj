package cangjiecoderagent

import stdx.encoding.json.*
import cangjiecoderagent.common.*
import cangjiecoderagent.ai.*
import cangjiecoderagent.client.*
import cangjiecoderagent.planner.*

@Test
class AgentHelpersTest {
    @TestCase
    func extractJsonObjectTextReadsMarkdownFence() {
        let text = "before\n```json\n{\"summary\":\"ok\",\"steps\":[{\"tool\":\"workspace.list_files\",\"arguments\":{},\"reason\":\"scan\"}]}\n```\nafter"
        let json = extractJsonObjectText(text)
        @Expect(json.contains("workspace.list_files"))
        @Expect(json.startsWith("{"))
    }

    @TestCase
    func appendValidationStepsAddsBuildAndTestForCreateFile() {
        let args = JsonObject()
        args.put("path", JsonString("src/generated_helper.cj"))
        let steps = appendValidationSteps([PlannedToolCall("workspace.create_file", args, "create helper")], allowedTools: ["workspace.create_file", "workspace.run_build", "workspace.run_test"])
        @Expect(steps.size == 3)
        @Expect(steps[1].tool, "workspace.run_build")
        @Expect(steps[2].tool, "workspace.run_test")
    }

    @TestCase
    func appendValidationStepsTreatsEditAstNodeAsMutation() {
        let args = JsonObject()
        args.put("path", JsonString("src/main.cj"))
        let steps = appendValidationSteps([PlannedToolCall("cangjie.edit_ast_node", args, "edit")], allowedTools: ["cangjie.edit_ast_node", "workspace.run_build", "workspace.run_test"])
        @Expect(steps.size == 3)
        @Expect(steps[1].tool, "workspace.run_build")
        @Expect(steps[2].tool, "workspace.run_test")
    }

    @TestCase
    func parseConfigKeepsWholePromptTail() {
        let config = parseConfig([
            "--workspace",
            "/home/runner/work/CangjieCoder/CangjieCoder",
            "--max-rounds",
            "3",
            "--prompt",
            "请",
            "创建",
            "JsonParser",
            "示例项目"
        ])
        @Expect(config.prompt, "请 创建 JsonParser 示例项目")
        @Expect(config.maxRounds, 3)
    }

    @TestCase
    func parseConfigReturnsEmptyPromptForHelpFlag() {
        let config = parseConfig(["--help"])
        @Expect(config.prompt.trimAscii().isEmpty())
    }

    @TestCase
    func parseConfigHandlesShortOptionFlags() {
        let config = parseConfig([
            "-w",
            "/home/runner/work/CangjieCoder/CangjieCoder",
            "-n",
            "5",
            "-p",
            "请分析代码"
        ])
        @Expect(config.maxRounds, 5)
        @Expect(config.prompt, "请分析代码")
    }

    @TestCase
    func parseConfigUsesNonOptionsAsPromptWithoutFlag() {
        let config = parseConfig([
            "--workspace",
            "/home/runner/work/CangjieCoder/CangjieCoder",
            "--",
            "请创建示例项目"
        ])
        @Expect(config.prompt, "请创建示例项目")
    }

    @TestCase
    func parseConfigFallsBackOnInvalidArgs() {
        let config = parseConfig(["--max-rounds"])
        @Expect(config.prompt.trimAscii().isEmpty())
    }

    @TestCase
    func parsePlanFiltersUnsupportedModelSteps() {
        let context = AgentPlanningContext(
            "分析当前工程",
            "{\"tools\":[{\"name\":\"workspace.list_files\"},{\"name\":\"workspace.read_file\"}]}",
            "{\"ok\":true,\"data\":{\"files\":[\"README.md\",\"cjpm.toml\",\"src/main.cj\"]}}"
        )
        let plan = parsePlan("{\"summary\":\"demo\",\"steps\":[{\"tool\":\"unknown.tool\",\"arguments\":{},\"reason\":\"bad\"},{\"tool\":\"workspace.read_file\",\"arguments\":{\"path\":\"README.md\"},\"reason\":\"good\"}]}", context)
        @Expect(plan.steps.size == 1)
        @Expect(plan.steps[0].tool, "workspace.read_file")
    }

    @TestCase
    func fallbackPlanReadsWorkspaceContextForAnalysisTasks() {
        let context = AgentPlanningContext(
            "请分析并优化这个仓颉项目",
            "{\"tools\":[{\"name\":\"workspace.list_files\"},{\"name\":\"workspace.read_file\"},{\"name\":\"cangjie.lsp_document_symbols\"},{\"name\":\"cangjie.analyze_file\"},{\"name\":\"workspace.run_build\"},{\"name\":\"workspace.run_test\"}]}",
            "{\"ok\":true,\"data\":{\"files\":[\"README.md\",\"cjpm.toml\",\"src/main.cj\"]}}"
        )
        let plan = parsePlan("", context)
        @Expect(plan.steps.size == 6)
        @Expect(plan.steps[0].tool, "workspace.list_files")
        @Expect(plan.steps[1].tool, "workspace.read_file")
        @Expect(jsonField(plan.steps[1].arguments, "path"), "cjpm.toml")
        @Expect(plan.steps[2].tool, "cangjie.lsp_document_symbols")
        @Expect(plan.steps[3].tool, "cangjie.analyze_file")
        @Expect(plan.steps[4].tool, "workspace.run_build")
        @Expect(plan.steps[5].tool, "workspace.run_test")
    }

    @TestCase
    func parsePlanAllowsExplicitEmptyCompletionPlan() {
        let context = AgentPlanningContext(
            "完成任务",
            "{\"tools\":[{\"name\":\"workspace.list_files\"}]}",
            "{\"ok\":true,\"data\":{\"files\":[\"README.md\"]}}"
        )
        let plan = parsePlan("{\"summary\":\"done\",\"steps\":[]}", context)
        @Expect(plan.summary, "done")
        @Expect(plan.steps.size == 0)
    }

    @TestCase
    func shouldTriggerFollowUpRoundAfterInspectionOnlyMutationPrompt() {
        let roundExecutions = [
            ToolExecution("workspace.list_files", JsonObject(), true, "ok", ""),
            ToolExecution("workspace.read_file", JsonObject(), true, "ok", "")
        ]
        @Expect(shouldTriggerFollowUpRound("请修复当前工程问题", roundExecutions, roundExecutions, 0, 2))
    }

    @TestCase
    func filterPendingStepsSkipsAlreadyExecutedStep() {
        let arguments = JsonObject()
        arguments.put("path", JsonString("README.md"))
        let steps = filterPendingSteps(
            [PlannedToolCall("workspace.read_file", arguments, "read"), PlannedToolCall("workspace.list_files", JsonObject(), "list")],
            [ToolExecution("workspace.read_file", arguments, true, "ok", "")]
        )
        @Expect(steps.size == 1)
        @Expect(steps[0].tool, "workspace.list_files")
    }

    @TestCase
    func extractJsonObjectTextHandlesMultipleJsonBlocks() {
        let text = "Here are two objects:\n{\"type\":\"config\"}\n{\"summary\":\"plan\",\"steps\":[]}"
        let json = extractJsonObjectText(text)
        @Expect(json.contains("steps"))
        @Expect(json.contains("summary"))
    }

    @TestCase
    func extractJsonObjectTextHandlesBracesInStrings() {
        let text = "{\"summary\":\"object with { braces } inside\",\"steps\":[]}"
        let json = extractJsonObjectText(text)
        @Expect(json.contains("steps"))
        @Expect(json.contains("summary"))
    }

    @TestCase
    func extractJsonObjectTextHandlesBracesAfterJson() {
        let text = "Plan: {\"summary\":\"ok\",\"steps\":[]} and here is code { func() {} }"
        let json = extractJsonObjectText(text)
        @Expect(json.contains("summary"))
        @Expect(json.contains("steps"))
    }

    @TestCase
    func extractJsonObjectTextReturnsEmptyForPlainText() {
        let json = extractJsonObjectText("no json here at all")
        @Expect(json.isEmpty())
    }

    @TestCase
    func buildCompactWorkspaceSummaryExtractsKeyInfo() {
        let snapshot = "{\"ok\":true,\"data\":{\"count\":5,\"files\":[\"README.md\",\"cjpm.toml\",\"src/main.cj\",\"src/helper.cj\",\"src/helper_test.cj\"]}}"
        let summary = buildCompactWorkspaceSummary(snapshot)
        @Expect(summary.contains("5 files total"))
        @Expect(summary.contains("README.md"))
        @Expect(summary.contains("cjpm.toml"))
        @Expect(summary.contains("src/main.cj"))
        @Expect(summary.contains("src/helper.cj"))
        @Expect(!summary.contains("helper_test.cj"))
    }

    @TestCase
    func buildCompactWorkspaceSummaryHandlesEmptySnapshot() {
        let summary = buildCompactWorkspaceSummary("{}")
        @Expect(summary.contains("0 files total"))
    }

    @TestCase
    func fallbackPlanUsesRunCommandForNewProject() {
        // 新建项目应使用 workspace.run_command 调用 cjpm init，而非内置模板
        let context = AgentPlanningContext(
            "创建一个新项目",
            "{\"tools\":[{\"name\":\"workspace.run_command\"},{\"name\":\"workspace.run_build\"},{\"name\":\"workspace.list_files\"}]}",
            "{\"ok\":true,\"data\":{\"files\":[]}}"
        )
        let plan = buildFallbackPlan(context)
        @Expect(plan.steps.size > 0)
        @Expect(plan.steps[0].tool, "workspace.run_command")
    }

    @TestCase
    func fallbackPlanSearchesSkillsForFeatureQuestions() {
        // 当提示词涉及语言特性时，应优先搜索技能文档
        let context = AgentPlanningContext(
            "怎么写仓颉的 enum 模式匹配",
            "{\"tools\":[{\"name\":\"skills.search\"},{\"name\":\"workspace.list_files\"},{\"name\":\"workspace.read_file\"}]}",
            "{\"ok\":true,\"data\":{\"files\":[\"README.md\"]}}"
        )
        let plan = buildFallbackPlan(context)
        @Expect(plan.steps.size > 0)
        @Expect(plan.steps[0].tool, "skills.search")
    }

    @TestCase
    func fallbackPlanInspectsCjpmTomlWhenPresent() {
        // 工作区包含 cjpm.toml 时，fallback plan 应读取它
        let context = AgentPlanningContext(
            "请分析这个项目",
            "{\"tools\":[{\"name\":\"workspace.list_files\"},{\"name\":\"workspace.read_file\"},{\"name\":\"workspace.run_build\"}]}",
            "{\"ok\":true,\"data\":{\"files\":[\"README.md\",\"cjpm.toml\",\"src/main.cj\"]}}"
        )
        let plan = buildFallbackPlan(context)
        var readsCjpmToml = false
        for (step in plan.steps) {
            if (step.tool == "workspace.read_file" && jsonField(step.arguments, "path") == "cjpm.toml") {
                readsCjpmToml = true
            }
        }
        @Expect(readsCjpmToml)
    }
}
