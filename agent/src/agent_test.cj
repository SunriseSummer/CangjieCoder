package cangjiecoderagent

import stdx.encoding.json.*

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
    func appendValidationStepsAddsBuildAndTestForBootstrap() {
        let args = JsonObject()
        args.put("path", JsonString("target/generated-json-parser"))
        let steps = appendValidationSteps([PlannedToolCall("project.bootstrap_json_parser", args, "bootstrap")], allowedTools: ["project.bootstrap_json_parser", "workspace.run_build", "workspace.run_test"])
        @Expect(steps.size == 3)
        @Expect(steps[1].tool, "workspace.run_build")
        @Expect(jsonField(steps[1].arguments, "path"), "target/generated-json-parser")
        @Expect(steps[2].tool, "workspace.run_test")
    }

    @TestCase
    func appendValidationStepsTreatsCreateFileAsMutation() {
        let args = JsonObject()
        args.put("path", JsonString("src/generated_helper.cj"))
        let steps = appendValidationSteps([PlannedToolCall("workspace.create_file", args, "create helper")], allowedTools: ["workspace.create_file", "workspace.run_build", "workspace.run_test"])
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
    func extractTargetPathFromPromptStopsAtChinesePunctuation() {
        let path = extractTargetPathFromPrompt("请创建示例项目到 target/agent-e2e-demo，并执行测试")
        @Expect(path, "target/agent-e2e-demo")
    }

    @TestCase
    func parsePlanFiltersUnsupportedModelSteps() {
        let context = AgentPlanningContext(
            "分析当前工程",
            "{\"tools\":[{\"name\":\"workspace.list_files\"},{\"name\":\"workspace.read_file\"}]}",
            "{\"ok\":true,\"data\":{\"files\":[\"README.md\",\"cjpm.toml\",\"src/main.cj\"]}}",
            "{\"ok\":true,\"data\":{\"projects\":[]}}"
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
            "{\"ok\":true,\"data\":{\"files\":[\"README.md\",\"cjpm.toml\",\"src/main.cj\"]}}",
            "{\"ok\":true,\"data\":{\"projects\":[]}}"
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
            "{\"ok\":true,\"data\":{\"files\":[\"README.md\"]}}",
            "{\"ok\":true,\"data\":{\"projects\":[]}}"
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
}
