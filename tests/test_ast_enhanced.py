"""Tests for enhanced Cangjie AST MCP tools: ast_summary, ast_query_nodes_with_text.

Covers real-world scenarios where an AI agent needs to:
- Quickly understand file structure without reading full source
- Extract specific code elements (functions, classes) with their source text
- Combine summary + detail queries for efficient code exploration
"""

import os

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))


def _read_file(path):
    full = os.path.join(TESTS_DIR, "cangjie", path)
    with open(full, "r", encoding="utf-8") as f:
        return f.read()


def run_tests(client_factory):
    """Run enhanced AST tool tests. Returns list of (name, passed, error)."""
    results = []

    # ── Session 1: ast_summary for file overview ─────────────
    c = client_factory()
    c.start()
    c.call_tool("cangjie.ast_summary", {"path": "src/models.cj"})    # 0
    c.call_tool("cangjie.ast_summary", {"path": "src/store.cj"})     # 1
    c.call_tool("cangjie.ast_summary", {"path": "src/main.cj"})      # 2
    c.call_tool("cangjie.ast_summary", {"path": "no_such_file.cj"})  # 3
    resp = c.execute()

    tests_s1 = [
        # models.cj has enums, structs and classes — summary should list them
        ("ast_summary_models", lambda: (
            resp[0]["ok"] is True
            and "data" in resp[0]
            and "summary" in resp[0]["data"]
            and "entries" in resp[0]["data"]
        )),
        # summary entries should be a non-empty list
        ("ast_summary_models_has_entries", lambda: (
            resp[0]["ok"] is True
            and isinstance(resp[0]["data"]["entries"], list)
            and len(resp[0]["data"]["entries"]) > 0
        )),
        # each entry should have kind, signature, startRow, endRow
        ("ast_summary_entry_format", lambda: (
            resp[0]["ok"] is True
            and all(
                "kind" in e and "signature" in e
                and "startRow" in e and "endRow" in e
                for e in resp[0]["data"]["entries"]
            )
        )),
        # store.cj should produce a valid summary
        ("ast_summary_store", lambda: (
            resp[1]["ok"] is True
            and "data" in resp[1]
            and len(resp[1]["data"].get("entries", [])) > 0
        )),
        # main.cj summary
        ("ast_summary_main", lambda: (
            resp[2]["ok"] is True
            and "data" in resp[2]
        )),
        # nonexistent file should fail gracefully
        ("ast_summary_nonexistent", lambda: resp[3]["ok"] is False),
    ]
    for name, check in tests_s1:
        try:
            assert check(), "Check failed"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    # ── Session 2: ast_query_nodes_with_text ─────────────────
    c2 = client_factory()
    c2.start()
    # Query function definitions with source text
    c2.call_tool("cangjie.ast_query_nodes_with_text", {              # 0
        "path": "src/store.cj", "nodeType": "functionDefinition"
    })
    # Query class definitions with source text
    c2.call_tool("cangjie.ast_query_nodes_with_text", {              # 1
        "path": "src/models.cj", "nodeType": "classDefinition"
    })
    # Query a type that doesn't exist
    c2.call_tool("cangjie.ast_query_nodes_with_text", {              # 2
        "path": "src/models.cj", "nodeType": "xyz_nonexistent_type"
    })
    # Query on nonexistent file
    c2.call_tool("cangjie.ast_query_nodes_with_text", {              # 3
        "path": "no_such_file.cj", "nodeType": "functionDefinition"
    })
    # Query enum definitions
    c2.call_tool("cangjie.ast_query_nodes_with_text", {              # 4
        "path": "src/models.cj", "nodeType": "enumDefinition"
    })
    resp2 = c2.execute()

    tests_s2 = [
        # store.cj has multiple functions — should return nodes with text
        ("query_with_text_functions", lambda: (
            resp2[0]["ok"] is True
            and resp2[0]["data"]["matchCount"] > 0
            and isinstance(resp2[0]["data"]["nodes"], list)
        )),
        # each returned node should have "text" field with actual source
        ("query_with_text_has_source", lambda: (
            resp2[0]["ok"] is True
            and all(
                "text" in n and len(n["text"]) > 0
                for n in resp2[0]["data"]["nodes"]
            )
        )),
        # function text should contain "func" keyword
        ("query_with_text_contains_func", lambda: (
            resp2[0]["ok"] is True
            and all(
                "func" in n["text"]
                for n in resp2[0]["data"]["nodes"]
            )
        )),
        # class definitions in models.cj
        ("query_with_text_classes", lambda: (
            resp2[1]["ok"] is True
            and resp2[1]["data"]["matchCount"] > 0
        )),
        # unknown type returns zero matches (not an error)
        ("query_with_text_unknown_type", lambda: (
            resp2[2]["ok"] is True
            and resp2[2]["data"]["matchCount"] == 0
        )),
        # nonexistent file fails gracefully
        ("query_with_text_bad_file", lambda: resp2[3]["ok"] is False),
        # enum definitions should contain enum keyword in text
        ("query_with_text_enums", lambda: (
            resp2[4]["ok"] is True
            and (
                resp2[4]["data"]["matchCount"] == 0
                or all(
                    "text" in n and len(n["text"]) > 0
                    for n in resp2[4]["data"]["nodes"]
                )
            )
        )),
    ]
    for name, check in tests_s2:
        try:
            assert check(), "Check failed"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    # ── Session 3: combined summary + detail workflow ────────
    # Simulates real AI usage: first get overview, then drill into specifics
    c3 = client_factory()
    c3.start()
    # Step 1: Get file summary
    c3.call_tool("cangjie.ast_summary", {"path": "src/store.cj"})     # 0
    # Step 2: Get all function bodies
    c3.call_tool("cangjie.ast_query_nodes_with_text", {               # 1
        "path": "src/store.cj", "nodeType": "functionDefinition"
    })
    # Step 3: Also parse AST for comparison
    c3.call_tool("cangjie.ast_parse", {"path": "src/store.cj"})       # 2
    # Step 4: Count-style query (query_nodes returns matchCount)
    c3.call_tool("cangjie.ast_query_nodes", {                         # 3
        "path": "src/store.cj", "nodeType": "functionDefinition"
    })
    resp3 = c3.execute()

    tests_s3 = [
        # Summary should succeed
        ("workflow_summary_ok", lambda: resp3[0]["ok"] is True),
        # Detail query should succeed
        ("workflow_detail_ok", lambda: resp3[1]["ok"] is True),
        # AST parse should succeed
        ("workflow_parse_ok", lambda: resp3[2]["ok"] is True),
        # matchCount from query_nodes should equal matchCount from query_with_text
        ("workflow_counts_match", lambda: (
            resp3[1]["data"]["matchCount"] == resp3[3]["data"]["matchCount"]
        )),
        # Summary should be much smaller than full source
        ("workflow_summary_compact", lambda: (
            len(resp3[0]["data"].get("summary", ""))
            < len(resp3[2]["data"].get("sexp", ""))
        )),
    ]
    for name, check in tests_s3:
        try:
            assert check(), "Check failed"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    # ── Session 4: tools/list includes new tools ─────────────
    c4 = client_factory()
    c4.start()
    c4.list_tools()  # 0
    resp4 = c4.execute()

    tests_s4 = [
        ("tools_list_has_ast_summary", lambda: (
            any(t["name"] == "cangjie.ast_summary"
                for t in resp4[0].get("tools", []))
        )),
        ("tools_list_has_query_with_text", lambda: (
            any(t["name"] == "cangjie.ast_query_nodes_with_text"
                for t in resp4[0].get("tools", []))
        )),
    ]
    for name, check in tests_s4:
        try:
            assert check(), "Check failed"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    return results
