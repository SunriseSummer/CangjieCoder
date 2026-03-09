package cangjiecoder

import stdx.encoding.json.*

struct ToolArgSpec {
    public ToolArgSpec(let name: String,
                       let kind: String,
                       let description: String,
                       let required: Bool) {}
}

struct ToolDefinition {
    public ToolDefinition(let name: String,
                          let description: String,
                          let args: Array<ToolArgSpec>) {}
}

func buildToolDefinitions(): Array<ToolDefinition> {
    return [
        ToolDefinition("skills.search", "Search built-in Cangjie skills stored in .github/skills.", [
            ToolArgSpec("query", "string", "Search keywords for skills lookup.", true)
        ]),
        ToolDefinition("workspace.read_file", "Read a file inside the repository root.", [
            ToolArgSpec("path", "string", "Repository-relative or absolute in-repo path.", true)
        ]),
        ToolDefinition("workspace.list_files", "Recursively list files inside the repository root or a subdirectory.", [
            ToolArgSpec("path", "string", "Optional repository-relative directory to list from. Defaults to the workspace root.", false),
            ToolArgSpec("limit", "integer", "Maximum number of files to return. Defaults to 200.", false)
        ]),
        ToolDefinition("workspace.search_text", "Search for exact text matches inside workspace files.", [
            ToolArgSpec("query", "string", "Exact text query to search for.", true),
            ToolArgSpec("path", "string", "Optional repository-relative directory to search in. Defaults to the workspace root.", false),
            ToolArgSpec("limit", "integer", "Maximum number of matches to return. Defaults to 20.", false)
        ]),
        ToolDefinition("workspace.replace_text", "Replace exactly one matched text block inside an existing file.", [
            ToolArgSpec("path", "string", "Repository-relative or absolute in-repo path.", true),
            ToolArgSpec("oldText", "string", "Exact text to replace.", true),
            ToolArgSpec("newText", "string", "Replacement text.", true)
        ]),
        ToolDefinition("workspace.run_build", "Run cjpm build inside the workspace or a subdirectory.", [
            ToolArgSpec("path", "string", "Optional repository-relative working directory. Defaults to the workspace root.", false)
        ]),
        ToolDefinition("workspace.run_test", "Run cjpm test inside the workspace or a subdirectory.", [
            ToolArgSpec("path", "string", "Optional repository-relative working directory. Defaults to the workspace root.", false)
        ]),
        ToolDefinition("workspace.run_command", "Run a workspace command from a restricted allowlist for agent automation.", [
            ToolArgSpec("command", "string", "Allowed command name such as cjpm, cjc, cjlint, tree-sitter, grep, or find.", true),
            ToolArgSpec("args", "array", "Optional positional arguments for the allowed command.", false),
            ToolArgSpec("path", "string", "Optional repository-relative working directory. Defaults to the workspace root.", false)
        ]),
        ToolDefinition("cangjie.analyze_file", "Run tree-sitter/cjlint/cjc based analysis for a Cangjie source file.", [
            ToolArgSpec("path", "string", "Cangjie source file path.", true)
        ]),
        ToolDefinition("project.list_examples", "List built-in Cangjie example projects that can be bootstrapped into the workspace.", []),
        ToolDefinition("project.bootstrap_json_parser", "Copy the built-in JsonParser example project into a target workspace path.", [
            ToolArgSpec("path", "string", "Destination directory to create inside the workspace.", true)
        ]),
        ToolDefinition("cangjie.lsp_status", "Inspect whether a Cangjie LSP binary is configured or discoverable.", []),
        ToolDefinition("cangjie.lsp_probe", "Run a lightweight initialize/shutdown probe against the configured Cangjie LSP server.", []),
        ToolDefinition("cangjie.lsp_document_symbols", "Query the configured Cangjie LSP server for document symbols in a source file.", [
            ToolArgSpec("path", "string", "Cangjie source file path.", true)
        ]),
        ToolDefinition("cangjie.lsp_workspace_symbols", "Query the configured Cangjie LSP server for workspace-level symbol matches.", [
            ToolArgSpec("query", "string", "Symbol name or fuzzy symbol query. Empty string requests a broad symbol scan.", false)
        ]),
        ToolDefinition("cangjie.edit_ast_node", "Replace the selected AST node using tree-sitter parse ranges.", [
            ToolArgSpec("path", "string", "Cangjie source file path.", true),
            ToolArgSpec("nodeType", "string", "Tree-sitter node type to replace.", true),
            ToolArgSpec("replacement", "string", "Replacement source text.", true),
            ToolArgSpec("index", "integer", "Zero-based match index when multiple nodes match. Defaults to 0 if omitted.", false)
        ])
    ]
}

func toolDefinitionsJson(): String {
    let tools = JsonArray()
    for (tool in buildToolDefinitions()) {
        let item = JsonObject()
        item.put("name", JsonString(tool.name))
        item.put("description", JsonString(tool.description))

        let schema = JsonObject()
        schema.put("type", JsonString("object"))
        let properties = JsonObject()
        let required = JsonArray()
        for (arg in tool.args) {
            let property = JsonObject()
            property.put("type", JsonString(arg.kind))
            property.put("description", JsonString(arg.description))
            properties.put(arg.name, property)
            if (arg.required) {
                required.add(JsonString(arg.name))
            }
        }
        schema.put("properties", properties)
        schema.put("required", required)
        item.put("inputSchema", schema)
        tools.add(item)
    }
    let root = JsonObject()
    root.put("tools", tools)
    return root.toString()
}
