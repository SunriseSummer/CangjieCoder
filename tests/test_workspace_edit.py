"""Tests for workspace.replace_text and workspace.rollback MCP tools.

Tests text replacement, rollback after single/multiple edits, and
overwrite-then-rollback.  Verifies the service's code management and
replay (backup / restore) capabilities.
"""

import os

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))


def _read_file(path):
    """Read a test project file directly from disk."""
    full = os.path.join(TESTS_DIR, "cangjie", path)
    with open(full, "r", encoding="utf-8") as f:
        return f.read()


def run_tests(client_factory):
    """Run edit & rollback tests. Returns list of (name, passed, error)."""
    results = []

    # Pre-read original content from disk
    orig_store = _read_file("src/store.cj")
    orig_main = _read_file("src/main.cj")

    # ── Session 1: single edit + rollback ────────────────────
    c = client_factory()
    c.start()
    c.call_tool("workspace.replace_text", {                     # 0
        "path": "src/store.cj",
        "oldText": "func add(task:",
        "newText": "func addTask(task:"
    })
    c.call_tool("workspace.read_file", {"path": "src/store.cj"})  # 1
    c.call_tool("workspace.replace_text", {                     # 2
        "path": "src/store.cj",
        "oldText": "this_text_does_not_exist_anywhere_12345",
        "newText": "replacement"
    })
    c.call_tool("workspace.replace_text", {                     # 3
        "path": "nonexistent.cj",
        "oldText": "a", "newText": "b"
    })
    c.call_tool("workspace.rollback")                            # 4
    c.call_tool("workspace.read_file", {"path": "src/store.cj"})  # 5
    resp = c.execute()

    tests_s1 = [
        ("replace_text_basic", lambda: resp[0]["ok"] is True),
        ("replace_text_verify", lambda: (
            "func addTask(task:" in resp[1]["data"]["content"]
        )),
        ("replace_text_not_found", lambda: resp[2]["ok"] is False),
        ("replace_text_nonexistent_file", lambda: resp[3]["ok"] is False),
        ("rollback_restores_single_edit", lambda: (
            resp[4]["ok"] is True
        )),
        ("rollback_content_restored", lambda: (
            resp[5]["data"]["content"] == orig_store
        )),
    ]
    for name, check in tests_s1:
        try:
            assert check(), "Check failed"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    # ── Session 2: rollback with no pending changes ──────────
    c2 = client_factory()
    c2.start()
    c2.call_tool("workspace.rollback")                            # 0
    resp2 = c2.execute()

    name = "rollback_no_pending_changes"
    try:
        assert resp2[0]["ok"] is True, "Should succeed with no backups"
        results.append((name, True, ""))
    except Exception as e:
        results.append((name, False, str(e)))

    # ── Session 3: multiple edits then rollback ──────────────
    c3 = client_factory()
    c3.start()
    c3.call_tool("workspace.replace_text", {                     # 0
        "path": "src/main.cj",
        "oldText": 'store.add(Task("编写单元测试"',
        "newText": 'store.add(Task("编写集成测试"'
    })
    c3.call_tool("workspace.replace_text", {                     # 1
        "path": "src/store.cj",
        "oldText": "func complete(",
        "newText": "func finish("
    })
    c3.call_tool("workspace.read_file", {"path": "src/main.cj"})  # 2
    c3.call_tool("workspace.read_file", {"path": "src/store.cj"})  # 3
    c3.call_tool("workspace.rollback")                             # 4
    c3.call_tool("workspace.read_file", {"path": "src/main.cj"})  # 5
    c3.call_tool("workspace.read_file", {"path": "src/store.cj"})  # 6
    resp3 = c3.execute()

    tests_s3 = [
        ("multi_edit_main", lambda: resp3[0]["ok"] is True),
        ("multi_edit_store", lambda: resp3[1]["ok"] is True),
        ("multi_edit_verify_main", lambda: (
            '编写集成测试' in resp3[2]["data"]["content"]
        )),
        ("multi_edit_verify_store", lambda: (
            "func finish(" in resp3[3]["data"]["content"]
        )),
        ("multi_rollback", lambda: resp3[4]["ok"] is True),
        ("multi_restored_main", lambda: (
            resp3[5]["data"]["content"] == orig_main
        )),
        ("multi_restored_store", lambda: (
            resp3[6]["data"]["content"] == orig_store
        )),
    ]
    for name, check in tests_s3:
        try:
            assert check(), "Check failed"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    # ── Session 4: create_file overwrite then rollback ───────
    c4 = client_factory()
    c4.start()
    c4.call_tool("workspace.create_file", {                      # 0
        "path": "src/store.cj",
        "content": "package testproject\n// overwritten\n",
        "overwrite": True
    })
    c4.call_tool("workspace.read_file", {"path": "src/store.cj"})  # 1
    c4.call_tool("workspace.rollback")                              # 2
    c4.call_tool("workspace.read_file", {"path": "src/store.cj"})  # 3
    resp4 = c4.execute()

    tests_s4 = [
        ("overwrite_succeeds", lambda: resp4[0]["ok"] is True),
        ("overwrite_verify", lambda: (
            "// overwritten" in resp4[1]["data"]["content"]
        )),
        ("overwrite_rollback", lambda: resp4[2]["ok"] is True),
        ("overwrite_restored", lambda: (
            resp4[3]["data"]["content"] == orig_store
        )),
    ]
    for name, check in tests_s4:
        try:
            assert check(), "Check failed"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    return results
