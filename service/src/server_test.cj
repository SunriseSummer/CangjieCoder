package cangjiecoder

import std.env.*
import std.fs.*
import cangjiecoder.common.*
import cangjiecoder.json.*
import cangjiecoder.lsp.*
import cangjiecoder.mcp.*
import cangjiecoder.skills.*
import cangjiecoder.analysis.*
import cangjiecoder.tools.*

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
    func runtimeInitializeReturnsCapabilities() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains("\"capabilities\""))
                @Expect(payload.contains("\"tools\""))
                @Expect(payload.contains("\"prompts\""))
                @Expect(payload.contains("\"resources\""))
            case None =>
                @Expect(false)
        }
    }

    @TestCase
    func runtimePingReturnsPong() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"ping\",\"params\":{}}")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains("\"pong\":true"))
                @Expect(payload.contains("\"id\":10"))
            case None =>
                @Expect(false)
        }
    }

    @TestCase
    func runtimeReturnsErrorForUnknownMethod() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"unknown/method\",\"params\":{}}")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains("\"error\""))
                @Expect(payload.contains("-32601"))
                @Expect(payload.contains("Unsupported MCP method"))
            case None =>
                @Expect(false)
        }
    }

    @TestCase
    func runtimeReturnsErrorForInvalidJson() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest("not valid json at all")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains("\"error\""))
                @Expect(payload.contains("-32700"))
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
    func runtimeToolsListIncludesAllToolCategories() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{}}")
        match (response) {
            case Some(payload) =>
                // Skills
                @Expect(payload.contains("skills.search"))
                // Workspace
                @Expect(payload.contains("workspace.read_file"))
                @Expect(payload.contains("workspace.replace_text"))
                @Expect(payload.contains("workspace.rollback"))
                // Build & Commands
                @Expect(payload.contains("workspace.run_build"))
                @Expect(payload.contains("workspace.run_test"))
                // AST
                @Expect(payload.contains("cangjie.ast_parse"))
                @Expect(payload.contains("cangjie.ast_query_nodes"))
                @Expect(payload.contains("cangjie.ast_list_nodes"))
                @Expect(payload.contains("cangjie.edit_ast_node"))
                // Analysis
                @Expect(payload.contains("cangjie.analyze_file"))
                // LSP
                @Expect(payload.contains("cangjie.lsp_status"))
                @Expect(payload.contains("cangjie.lsp_probe"))
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
    func runtimeReturnsErrorForUnknownTool() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"tools/call\",\"params\":{\"name\":\"nonexistent.tool\",\"arguments\":{}}}")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains("\"isError\":true"))
                @Expect(payload.contains("Unknown tool"))
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
    func mcpToolCallMarksErrorWhenNotOk() {
        let result = mcpToolCallResultJson(toolMessageJson(false, "failed", "something broke"))
        @Expect(result.contains("\"isError\":true"))
        @Expect(result.contains("\"structuredContent\""))
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
    func runtimeCanListWorkspaceFiles() {
        let workspace = Directory.createTemp(getTempDirectory())
        try {
            writeTextFile("${workspace.toString()}/a.cj", "package a")
            Directory.create("${workspace.toString()}/sub", recursive: true)
            writeTextFile("${workspace.toString()}/sub/b.cj", "package b")
            let runtime = createMcpRuntime(workspace.toString(), serviceRoot: getWorkingDirectory().toString())
            let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":13,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.list_files\",\"arguments\":{}}}")
            match (response) {
                case Some(payload) =>
                    @Expect(payload.contains("\"ok\":true"))
                    @Expect(payload.contains("a.cj"))
                    @Expect(payload.contains("b.cj"))
                case None =>
                    @Expect(false)
            }
        } finally {
            removeIfExists(workspace.toString(), recursive: true)
        }
    }

    @TestCase
    func runtimeCanSearchTextInWorkspace() {
        let workspace = Directory.createTemp(getTempDirectory())
        try {
            writeTextFile("${workspace.toString()}/sample.cj", "func uniqueSearchTarget(): Int64 {\n    42\n}\n")
            let runtime = createMcpRuntime(workspace.toString(), serviceRoot: getWorkingDirectory().toString())
            let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":14,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.search_text\",\"arguments\":{\"query\":\"uniqueSearchTarget\"}}}")
            match (response) {
                case Some(payload) =>
                    @Expect(payload.contains("\"ok\":true"))
                    @Expect(payload.contains("uniqueSearchTarget"))
                    @Expect(payload.contains("\"line\""))
                    @Expect(payload.contains("\"preview\""))
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

    @TestCase
    func runtimeCanReplaceTextViaToolsCall() {
        let workspace = Directory.createTemp(getTempDirectory())
        try {
            let filePath = "${workspace.toString()}/replace_test.txt"
            writeTextFile(filePath, "hello world text")
            globalBackupStore.clear()

            let runtime = createMcpRuntime(workspace.toString(), serviceRoot: getWorkingDirectory().toString())
            let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":16,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.replace_text\",\"arguments\":{\"path\":\"replace_test.txt\",\"oldText\":\"hello world\",\"newText\":\"goodbye world\"}}}")
            match (response) {
                case Some(payload) =>
                    @Expect(payload.contains("\"ok\":true"))
                    @Expect(readTextFile(filePath).contains("goodbye world"))
                case None =>
                    @Expect(false)
            }
        } finally {
            globalBackupStore.clear()
            removeIfExists(workspace.toString(), recursive: true)
        }
    }

    @TestCase
    func runtimeHandlesMultipleSequentialRequests() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())

        // First request: initialize
        let initResponse = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":20,\"method\":\"initialize\",\"params\":{}}")
        match (initResponse) {
            case Some(payload) => @Expect(payload.contains("\"CangjieCoder\""))
            case None => @Expect(false)
        }

        // Second request: ping
        let pingResponse = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":21,\"method\":\"ping\",\"params\":{}}")
        match (pingResponse) {
            case Some(payload) => @Expect(payload.contains("\"pong\":true"))
            case None => @Expect(false)
        }

        // Third request: tools/list
        let toolsResponse = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":22,\"method\":\"tools/list\",\"params\":{}}")
        match (toolsResponse) {
            case Some(payload) => @Expect(payload.contains("workspace.read_file"))
            case None => @Expect(false)
        }
    }

    @TestCase
    func encodeMcpFrameIncludesContentLength() {
        let body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}"
        let frame = encodeMcpFrame(body)
        @Expect(frame.contains("Content-Length:"))
        @Expect(frame.contains(body))
    }

    @TestCase
    func jsonRpcResultFormatsCorrectly() {
        let result = jsonRpcResult("42", "{\"value\":1}")
        @Expect(result.contains("\"jsonrpc\":\"2.0\""))
        @Expect(result.contains("\"id\":42"))
        @Expect(result.contains("\"result\":{\"value\":1}"))
    }

    @TestCase
    func jsonRpcErrorFormatsCorrectly() {
        let result = jsonRpcError("99", -32600, "Invalid Request")
        @Expect(result.contains("\"jsonrpc\":\"2.0\""))
        @Expect(result.contains("\"id\":99"))
        @Expect(result.contains("\"error\""))
        @Expect(result.contains("-32600"))
        @Expect(result.contains("Invalid Request"))
    }

    @TestCase
    func runtimeCanCreateFileWithOverwrite() {
        let workspace = Directory.createTemp(getTempDirectory())
        try {
            let filePath = "${workspace.toString()}/overwrite.txt"
            writeTextFile(filePath, "old content")
            globalBackupStore.clear()

            let runtime = createMcpRuntime(workspace.toString(), serviceRoot: getWorkingDirectory().toString())
            let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":17,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.create_file\",\"arguments\":{\"path\":\"overwrite.txt\",\"content\":\"new content\",\"overwrite\":true}}}")
            match (response) {
                case Some(payload) =>
                    @Expect(payload.contains("\"ok\":true"))
                    @Expect(readTextFile(filePath), "new content")
                case None =>
                    @Expect(false)
            }
        } finally {
            globalBackupStore.clear()
            removeIfExists(workspace.toString(), recursive: true)
        }
    }

    @TestCase
    func runtimeCanSearchTextWithEmptyQuery() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":18,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.search_text\",\"arguments\":{\"query\":\"\"}}}")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains("\"ok\":false"))
                @Expect(payload.contains("query must not be empty"))
            case None =>
                @Expect(false)
        }
    }
}
