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
    func stdioMcpCanCreateFileAndValidateWorkspace() {
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

            // 使用 workspace.create_file 创建文件并验证
            let createArgs = JsonObject()
            createArgs.put("path", JsonString("src/helper.cj"))
            createArgs.put("content", JsonString("package default\n\nfunc helper(): String {\n    \"ok\"\n}\n"))
            let createResult = client.callTool("workspace.create_file", createArgs)
            @Expect(jsonField(createResult, "ok"), "true")

            // 验证文件已创建
            let listArgs = JsonObject()
            let listResult = client.callTool("workspace.list_files", listArgs)
            @Expect(jsonField(listResult, "ok"), "true")

            // 读取刚创建的文件
            let readArgs = JsonObject()
            readArgs.put("path", JsonString("src/helper.cj"))
            let readResult = client.callTool("workspace.read_file", readArgs)
            @Expect(jsonField(readResult, "ok"), "true")
        } finally {
            removeIfExists(workspace.toString(), recursive: true)
        }
    }
}
