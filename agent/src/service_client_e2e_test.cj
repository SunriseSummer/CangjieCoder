package cangjiecoderagent

import std.env.*
import std.fs.*
import stdx.encoding.json.*
import cangjiecoderagent.common.*
import cangjiecoderagent.ai.*
import cangjiecoderagent.client.*

func currentServiceDir(): String {
    return resolveDefaultServiceDir(canonicalize(getWorkingDirectory().toString()).toString())
}

@Test
class AgentServiceClientE2eTest {
    @TestCase
    func stdioMcpCanBootstrapCreateFileAndValidateProject() {
        let workspace = Directory.createTemp(getTempDirectory())
        try {
            let config = AgentConfig(
                workspace.toString(),
                currentServiceDir(),
                "kimi",
                "kimi-k2.5",
                1,
                "e2e"
            )
            let client = ServiceClient(config)
            let toolsJson = client.listToolsJson()
            @Expect(toolsJson.contains("workspace.create_file"))
            @Expect(toolsJson.contains("cangjie.lsp_definition"))

            let bootstrapArgs = JsonObject()
            bootstrapArgs.put("path", JsonString("generated/e2e-json-parser"))
            let bootstrapResult = client.callTool("project.bootstrap_json_parser", bootstrapArgs)
            @Expect(jsonField(bootstrapResult, "ok"), "true")

            let createArgs = JsonObject()
            createArgs.put("path", JsonString("generated/e2e-json-parser/src/generated_helper.cj"))
            createArgs.put("content", JsonString("package json_parser\n\nfunc generatedHelper(): String {\n    \"ok\"\n}\n"))
            let createResult = client.callTool("workspace.create_file", createArgs)
            @Expect(jsonField(createResult, "ok"), "true")

            let validationArgs = JsonObject()
            validationArgs.put("path", JsonString("generated/e2e-json-parser"))
            let buildResult = client.callTool("workspace.run_build", validationArgs)
            @Expect(jsonField(buildResult, "ok"), "true")
            let testResult = client.callTool("workspace.run_test", validationArgs)
            @Expect(jsonField(testResult, "ok"), "true")
        } finally {
            removeIfExists(workspace.toString(), recursive: true)
        }
    }
}
