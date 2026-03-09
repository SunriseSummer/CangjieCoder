package cangjiecoder

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
    }
}
