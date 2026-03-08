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
        let steps = appendValidationSteps([PlannedToolCall("project.bootstrap_json_parser", args, "bootstrap")])
        @Expect(steps.size == 3)
        @Expect(steps[1].tool, "workspace.run_build")
        @Expect(jsonField(steps[1].arguments, "path"), "target/generated-json-parser")
        @Expect(steps[2].tool, "workspace.run_test")
    }

    @TestCase
    func parseConfigKeepsWholePromptTail() {
        let config = parseConfig([
            "--workspace",
            "/home/runner/work/CangjieCoder/CangjieCoder",
            "--prompt",
            "请",
            "创建",
            "JsonParser",
            "示例项目"
        ])
        @Expect(config.prompt, "请 创建 JsonParser 示例项目")
    }

    @TestCase
    func extractTargetPathFromPromptStopsAtChinesePunctuation() {
        let path = extractTargetPathFromPrompt("请创建示例项目到 target/agent-e2e-demo，并执行测试")
        @Expect(path, "target/agent-e2e-demo")
    }
}
