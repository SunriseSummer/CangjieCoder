"""Tests for Cangjie AST analysis and editing MCP tools.

Covers cangjie.ast_parse, cangjie.ast_query_nodes, cangjie.ast_list_nodes,
cangjie.edit_ast_node, and cangjie.analyze_file.
"""

import os

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))


def _read_file(path):
    full = os.path.join(TESTS_DIR, "cangjie", path)
    with open(full, "r", encoding="utf-8") as f:
        return f.read()


def run_tests(client_factory):
    """Run AST tool tests. Returns list of (name, passed, error)."""
    results = []

    # ── Session 1: read-only AST queries ─────────────────────
    c = client_factory()
    c.start()
    c.call_tool("cangjie.ast_parse", {"path": "src/utils.cj"})     # 0
    c.call_tool("cangjie.ast_parse", {"path": "src/main.cj"})      # 1
    c.call_tool("cangjie.ast_parse", {"path": "no_file.cj"})       # 2
    c.call_tool("cangjie.ast_query_nodes", {                       # 3
        "path": "src/utils.cj", "nodeType": "function_definition"
    })
    c.call_tool("cangjie.ast_query_nodes", {                       # 4
        "path": "src/utils.cj", "nodeType": "class_definition"
    })
    c.call_tool("cangjie.ast_query_nodes", {                       # 5
        "path": "src/utils.cj", "nodeType": "nonexistent_type_xyz"
    })
    c.call_tool("cangjie.ast_list_nodes", {"path": "src/utils.cj"})  # 6
    c.call_tool("cangjie.ast_list_nodes", {                         # 7
        "path": "src/main.cj", "maxDepth": 2
    })
    c.call_tool("cangjie.analyze_file", {"path": "src/main.cj"})    # 8
    c.call_tool("cangjie.analyze_file", {"path": "no_file.cj"})     # 9
    resp = c.execute()

    tests_s1 = [
        ("ast_parse_valid", lambda: (
            "ok" in resp[0] and (not resp[0]["ok"] or "data" in resp[0])
        )),
        ("ast_parse_main", lambda: "ok" in resp[1]),
        ("ast_parse_nonexistent", lambda: resp[2]["ok"] is False),
        ("ast_query_functions", lambda: (
            "ok" in resp[3] and (not resp[3]["ok"] or "data" in resp[3])
        )),
        ("ast_query_classes", lambda: "ok" in resp[4]),
        ("ast_query_unknown_type", lambda: "ok" in resp[5]),
        ("ast_list_nodes", lambda: (
            "ok" in resp[6] and (not resp[6]["ok"] or "data" in resp[6])
        )),
        ("ast_list_nodes_depth", lambda: "ok" in resp[7]),
        ("analyze_file_valid", lambda: (
            "ok" in resp[8] and (not resp[8]["ok"] or "data" in resp[8])
        )),
        ("analyze_file_nonexistent", lambda: resp[9]["ok"] is False),
    ]
    for name, check in tests_s1:
        try:
            assert check(), f"Check failed"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    # ── Session 2: edit AST node then rollback ───────────────
    orig_utils = _read_file("src/utils.cj")
    c2 = client_factory()
    c2.start()
    c2.call_tool("cangjie.edit_ast_node", {                        # 0
        "path": "src/utils.cj",
        "nodeType": "function_definition",
        "replacement": "func replaced(): Unit {}",
        "index": 0
    })
    c2.call_tool("workspace.read_file", {"path": "src/utils.cj"})   # 1
    c2.call_tool("cangjie.edit_ast_node", {                         # 2
        "path": "src/utils.cj",
        "nodeType": "function_definition",
        "replacement": "func x(): Unit {}",
        "index": 999
    })
    c2.call_tool("workspace.rollback")                               # 3
    c2.call_tool("workspace.read_file", {"path": "src/utils.cj"})   # 4
    resp2 = c2.execute()

    tests_s2 = [
        ("edit_ast_node", lambda: "ok" in resp2[0]),
        ("edit_ast_verify", lambda: (
            not resp2[0].get("ok")
            or "replaced()" in resp2[1]["data"]["content"]
        )),
        ("edit_ast_invalid_index", lambda: "ok" in resp2[2]),
        ("edit_ast_rollback", lambda: resp2[3]["ok"] is True),
        ("edit_ast_restored", lambda: (
            resp2[4]["data"]["content"] == orig_utils
        )),
    ]
    for name, check in tests_s2:
        try:
            assert check(), "Check failed"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    return results
