package cangjiecoder

@Test
class McpProtocolTest {
    @TestCase
    func toolsListIncludesSchemas() {
        let json = toolDefinitionsJson()
        @Expect(json.contains("\"inputSchema\""))
        @Expect(json.contains("conversation.chat"))
        @Expect(json.contains("cangjie.edit_ast_node"))
    }
}
