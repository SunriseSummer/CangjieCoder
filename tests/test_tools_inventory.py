"""Tests for MCP tool inventory completeness and consistency.

Verifies the tool list is accurate after removing project template tools
and that all expected tool categories are present.
"""


def run_tests(client_factory):
    """Run tool inventory tests. Returns list of (name, passed, error)."""
    results = []

    c = client_factory()
    c.start()
    c.list_tools()                                                  # 0
    resp = c.execute()

    tool_names = [t["name"] for t in resp[0].get("tools", [])]

    tests = [
        # Total count: should be exactly 24 after removing 3 project tools
        ("total_tool_count_is_24", lambda: len(tool_names) == 24),

        # Skills tools (3)
        ("has_skills_search", lambda: "skills.search" in tool_names),
        ("has_skills_batch_search", lambda: "skills.batch_search" in tool_names),
        ("has_skills_prompt_context", lambda: "skills.prompt_context" in tool_names),

        # Workspace file tools (4)
        ("has_workspace_read_file", lambda: "workspace.read_file" in tool_names),
        ("has_workspace_list_files", lambda: "workspace.list_files" in tool_names),
        ("has_workspace_search_text", lambda: "workspace.search_text" in tool_names),
        ("has_workspace_create_file", lambda: "workspace.create_file" in tool_names),

        # Workspace edit tools (2)
        ("has_workspace_replace_text", lambda: "workspace.replace_text" in tool_names),
        ("has_workspace_rollback", lambda: "workspace.rollback" in tool_names),

        # Workspace command tools (3)
        ("has_workspace_run_build", lambda: "workspace.run_build" in tool_names),
        ("has_workspace_run_test", lambda: "workspace.run_test" in tool_names),
        ("has_workspace_run_command", lambda: "workspace.run_command" in tool_names),

        # Analysis tools (1)
        ("has_cangjie_analyze_file", lambda: "cangjie.analyze_file" in tool_names),

        # AST tools (5)
        ("has_cangjie_ast_parse", lambda: "cangjie.ast_parse" in tool_names),
        ("has_cangjie_ast_query_nodes", lambda: "cangjie.ast_query_nodes" in tool_names),
        ("has_cangjie_ast_list_nodes", lambda: "cangjie.ast_list_nodes" in tool_names),
        ("has_cangjie_ast_summary", lambda: "cangjie.ast_summary" in tool_names),
        ("has_cangjie_ast_query_nodes_with_text", lambda: "cangjie.ast_query_nodes_with_text" in tool_names),

        # AST edit tool (1)
        ("has_cangjie_edit_ast_node", lambda: "cangjie.edit_ast_node" in tool_names),

        # LSP tools (5)
        ("has_cangjie_lsp_status", lambda: "cangjie.lsp_status" in tool_names),
        ("has_cangjie_lsp_probe", lambda: "cangjie.lsp_probe" in tool_names),
        ("has_cangjie_lsp_document_symbols", lambda: "cangjie.lsp_document_symbols" in tool_names),
        ("has_cangjie_lsp_workspace_symbols", lambda: "cangjie.lsp_workspace_symbols" in tool_names),
        ("has_cangjie_lsp_definition", lambda: "cangjie.lsp_definition" in tool_names),

        # Removed project template tools should NOT be present
        ("no_project_list_examples", lambda: "project.list_examples" not in tool_names),
        ("no_project_bootstrap_json_parser", lambda: "project.bootstrap_json_parser" not in tool_names),
        ("no_project_bootstrap", lambda: "project.bootstrap" not in tool_names),

        # Every tool must have a non-empty description
        ("all_tools_have_descriptions", lambda: all(
            len(t.get("description", "")) > 0
            for t in resp[0].get("tools", [])
        )),
    ]

    for name, check in tests:
        try:
            assert check(), "Check failed"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    return results
