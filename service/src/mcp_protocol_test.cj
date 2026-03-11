package cangjiecoder

import cangjiecoder.common.*
import cangjiecoder.mcp.*
import cangjiecoder.json.*
import cangjiecoder.tools.*
import cangjiecoder.workspace.*

@Test
class McpProtocolTest {
    @TestCase
    func toolsListIncludesSchemas() {
        let json = toolDefinitionsJson()
        @Expect(json.contains("\"inputSchema\""))
        @Expect(json.contains("workspace.create_file"))
        @Expect(json.contains("cangjie.lsp_document_symbols"))
        @Expect(json.contains("cangjie.lsp_workspace_symbols"))
        @Expect(json.contains("cangjie.lsp_definition"))
        @Expect(json.contains("cangjie.edit_ast_node"))
        @Expect(json.contains("workspace.list_files"))
        @Expect(json.contains("workspace.search_text"))
        @Expect(json.contains("workspace.run_build"))
        @Expect(json.contains("workspace.run_test"))
        @Expect(json.contains("workspace.run_command"))
        @Expect(json.contains("workspace.rollback"))
    }

    @TestCase
    func toolRegistryCoversAllDefinedTools() {
        let definitions = buildToolDefinitions()
        let registry = buildMcpToolRegistry()
        for (tool in definitions) {
            @Expect(registry.contains(tool.name))
        }
    }

    @TestCase
    func methodRegistryCoversCoreMcpMethods() {
        let registry = buildMcpMethodRegistry()
        @Expect(registry.contains("initialize"))
        @Expect(registry.contains("ping"))
        @Expect(registry.contains("notifications/initialized"))
        @Expect(registry.contains("tools/list"))
        @Expect(registry.contains("tools/call"))
    }
}
