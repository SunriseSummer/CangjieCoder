package cangjiecoder

import std.env.*
import std.fs.*
import cangjiecoder.common.*
import cangjiecoder.json.*
import cangjiecoder.lsp.*
import cangjiecoder.mcp.*
import cangjiecoder.skills.*
import cangjiecoder.analysis.*

@Test
class ServerMcpTest {
    @TestCase
    func runtimeInitializeReturnsServerInfo() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains("\"serverInfo\""))
                @Expect(payload.contains("\"CangjieCoder\""))
            case None =>
                @Expect(false)
        }
    }

    @TestCase
    func runtimeToolsListIncludesP0Tools() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains("workspace.list_files"))
                @Expect(payload.contains("workspace.search_text"))
                @Expect(payload.contains("workspace.run_command"))
                @Expect(payload.contains("workspace.create_file"))
                @Expect(payload.contains("cangjie.lsp_document_symbols"))
                @Expect(payload.contains("cangjie.lsp_workspace_symbols"))
                @Expect(payload.contains("cangjie.lsp_definition"))
            case None =>
                @Expect(false)
        }
    }

    @TestCase
    func runtimeCanReadWorkspaceFileViaToolsCall() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.read_file\",\"arguments\":{\"path\":\"README.md\"}}}")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains("\"structuredContent\""))
                @Expect(payload.contains("\"ok\":true"))
                @Expect(payload.contains("\"path\":\"README.md\""))
            case None =>
                @Expect(false)
        }
    }

    @TestCase
    func runtimeReturnsStructuredErrorForDisallowedCommand() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.run_command\",\"arguments\":{\"command\":\"rm\",\"args\":[\"-rf\",\"/\"]}}}")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains("\"isError\":true"))
                @Expect(payload.contains("Allowed commands"))
            case None =>
                @Expect(false)
        }
    }

    @TestCase
    func encodeAndExtractMcpFramesRoundTrip() {
        let ping = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}"
        let toolsList = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}"
        let payload = "${encodeMcpFrame(ping)}${encodeMcpFrame(toolsList)}"
        let bodies = extractLspBodies(payload)
        @Expect(bodies.size == 2)
        @Expect(bodies[0].contains("\"method\":\"ping\""))
        @Expect(bodies[1].contains("\"method\":\"tools/list\""))
    }

    @TestCase
    func workspaceRunCommandRejectsDisallowedCommand() {
        let result = workspaceRunCommandJson(getWorkingDirectory().toString(), "rm", [], "")
        @Expect(result.contains("\"ok\":false"))
        @Expect(result.contains("Allowed commands"))
    }

    @TestCase
    func mcpToolCallUsesStructuredContentBlocks() {
        let result = mcpToolCallResultJson(toolMessageJson(true, "done", "updated"))
        @Expect(result.contains("\"content\":["))
        @Expect(result.contains("\"structuredContent\""))
        @Expect(result.contains("\"isError\":false"))
    }

    @TestCase
    func notificationsWithoutIdDoNotReturnResponses() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\",\"params\":{}}")
        match (response) {
            case Some(_) =>
                @Expect(false)
            case None =>
                @Expect(true)
        }
    }

    @TestCase
    func runtimeCanCreateNestedWorkspaceFileViaToolsCall() {
        let workspace = Directory.createTemp(getTempDirectory())
        try {
            let runtime = createMcpRuntime(workspace.toString(), serviceRoot: getWorkingDirectory().toString())
            let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.create_file\",\"arguments\":{\"path\":\"nested/demo/generated.cj\",\"content\":\"package demo\\n\\nfunc generated(): Int64 {\\n    1\\n}\\n\"}}}")
            match (response) {
                case Some(payload) =>
                    @Expect(payload.contains("\"ok\":true"))
                    @Expect(exists("${workspace.toString()}/nested/demo/generated.cj"))
                case None =>
                    @Expect(false)
            }
        } finally {
            removeIfExists(workspace.toString(), recursive: true)
        }
    }

    @TestCase
    func runtimeRejectsCreateFileOverwriteByDefault() {
        let workspace = Directory.createTemp(getTempDirectory())
        try {
            let filePath = "${workspace.toString()}/demo.txt"
            writeTextFile(filePath, "old")
            let runtime = createMcpRuntime(workspace.toString(), serviceRoot: getWorkingDirectory().toString())
            let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.create_file\",\"arguments\":{\"path\":\"demo.txt\",\"content\":\"new\"}}}")
            match (response) {
                case Some(payload) =>
                    @Expect(payload.contains("\"ok\":false"))
                    @Expect(readTextFile(filePath), "old")
                case None =>
                    @Expect(false)
            }
        } finally {
            removeIfExists(workspace.toString(), recursive: true)
        }
    }

    @TestCase
    func runtimeRollbackRestoresReplacedText() {
        let workspace = Directory.createTemp(getTempDirectory())
        try {
            let filePath = "${workspace.toString()}/rollback_demo.txt"
            writeTextFile(filePath, "unique original content")
            globalBackupStore.clear()

            let runtime = createMcpRuntime(workspace.toString(), serviceRoot: getWorkingDirectory().toString())
            // 执行替换
            let replaceResponse = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.replace_text\",\"arguments\":{\"path\":\"rollback_demo.txt\",\"oldText\":\"unique original\",\"newText\":\"modified\"}}}")
            match (replaceResponse) {
                case Some(payload) => @Expect(payload.contains("\"ok\":true"))
                case None => @Expect(false)
            }
            @Expect(readTextFile(filePath).contains("modified"))

            // 执行回滚
            let rollbackResponse = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.rollback\",\"arguments\":{}}}")
            match (rollbackResponse) {
                case Some(payload) =>
                    @Expect(payload.contains("\"ok\":true"))
                    @Expect(payload.contains("Rolled back"))
                case None =>
                    @Expect(false)
            }
            @Expect(readTextFile(filePath), "unique original content")
        } finally {
            globalBackupStore.clear()
            removeIfExists(workspace.toString(), recursive: true)
        }
    }

    @TestCase
    func runtimeRollbackWithNoBackupsReportsEmpty() {
        globalBackupStore.clear()
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.rollback\",\"arguments\":{}}}")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains("\"ok\":true"))
                @Expect(payload.contains("No backups exist"))
            case None =>
                @Expect(false)
        }
    }

    @TestCase
    func toolRegistryIncludesRollback() {
        let registry = buildMcpToolRegistry()
        @Expect(registry.contains("workspace.rollback"))
    }
}
