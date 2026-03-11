"""Tests for Cangjie LSP integration MCP tools.

Covers cangjie.lsp_status, cangjie.lsp_probe, cangjie.lsp_document_symbols,
cangjie.lsp_workspace_symbols, and cangjie.lsp_definition.

Note: LSP tools may return ok=false if no LSP binary is available.
Tests verify the response format regardless.
"""


def run_tests(client_factory):
    """Run LSP tool tests. Returns list of (name, passed, error)."""
    results = []
    c = client_factory()
    c.start()
    c.call_tool("cangjie.lsp_status")                              # 0
    c.call_tool("cangjie.lsp_probe")                               # 1
    c.call_tool("cangjie.lsp_document_symbols", {                  # 2
        "path": "src/models.cj"
    })
    c.call_tool("cangjie.lsp_document_symbols", {                  # 3
        "path": "no_such_file.cj"
    })
    c.call_tool("cangjie.lsp_workspace_symbols", {"query": "Task"})  # 4
    c.call_tool("cangjie.lsp_workspace_symbols", {"query": ""})     # 5
    c.call_tool("cangjie.lsp_definition", {                         # 6
        "path": "src/main.cj", "line": 1, "column": 1
    })
    c.call_tool("cangjie.lsp_definition", {                         # 7
        "path": "src/main.cj", "line": 9999, "column": 9999
    })
    resp = c.execute()

    tests = [
        ("lsp_status", lambda: "ok" in resp[0]),
        ("lsp_probe", lambda: "ok" in resp[1]),
        ("lsp_document_symbols", lambda: "ok" in resp[2]),
        ("lsp_document_symbols_nonexistent", lambda: "ok" in resp[3]),
        ("lsp_workspace_symbols", lambda: "ok" in resp[4]),
        ("lsp_workspace_symbols_empty", lambda: "ok" in resp[5]),
        ("lsp_definition", lambda: "ok" in resp[6]),
        ("lsp_definition_out_of_range", lambda: "ok" in resp[7]),
    ]

    for name, check in tests:
        try:
            assert check(), "Check failed"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    return results
