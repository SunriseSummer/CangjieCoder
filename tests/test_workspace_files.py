"""Tests for workspace file operation MCP tools.

Covers workspace.read_file, workspace.list_files, workspace.search_text,
and workspace.create_file with common and edge-case scenarios.
"""

import os

TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
CREATED_FILES = []  # Track new files for cleanup


def cleanup_created_files():
    """Remove files created during tests (not tracked by rollback)."""
    workspace = os.path.join(TESTS_DIR, "cangjie")
    for rel_path in CREATED_FILES:
        full = os.path.join(workspace, rel_path)
        if os.path.isfile(full):
            os.remove(full)
        parent = os.path.dirname(full)
        if os.path.isdir(parent) and not os.listdir(parent):
            os.rmdir(parent)
    CREATED_FILES.clear()


def run_tests(client_factory):
    """Run workspace file tests. Returns list of (name, passed, error)."""
    results = []
    c = client_factory()
    c.start()

    # Queue all requests
    c.call_tool("workspace.read_file", {"path": "src/main.cj"})          # 0
    c.call_tool("workspace.read_file", {"path": "no_such_file.cj"})      # 1
    c.call_tool("workspace.read_file", {"path": "../../etc/passwd"})      # 2
    c.call_tool("workspace.list_files", {})                               # 3
    c.call_tool("workspace.list_files", {"path": "src"})                  # 4
    c.call_tool("workspace.list_files", {"limit": 1})                     # 5
    c.call_tool("workspace.search_text", {"query": "func"})               # 6
    c.call_tool("workspace.search_text", {
        "query": "xyzzy_nonexistent_text_99999"
    })                                                                    # 7
    c.call_tool("workspace.search_text", {
        "query": "TaskStore", "path": "src/store.cj"
    })                                                                    # 8
    c.call_tool("workspace.search_text", {"query": "func", "limit": 2})   # 9
    c.call_tool("workspace.create_file", {
        "path": "src/temp_test.cj",
        "content": "package testproject\n\nfunc temp(): Unit {}\n"
    })                                                                    # 10
    c.call_tool("workspace.read_file", {"path": "src/temp_test.cj"})      # 11
    c.call_tool("workspace.create_file", {
        "path": "src/main.cj", "content": "overwritten"
    })                                                                    # 12
    c.call_tool("workspace.create_file", {
        "path": "src/sub/nested.cj",
        "content": "package testproject\n"
    })                                                                    # 13

    resp = c.execute()

    tests = [
        ("read_file_existing", lambda: (
            resp[0]["ok"] is True and "main()" in resp[0]["data"]["content"]
        )),
        ("read_file_nonexistent", lambda: resp[1]["ok"] is False),
        ("read_file_path_traversal", lambda: resp[2]["ok"] is False),
        ("list_files_root", lambda: (
            resp[3]["ok"] is True and resp[3]["data"]["count"] > 0
        )),
        ("list_files_src", lambda: (
            resp[4]["ok"] is True and resp[4]["data"]["count"] > 0
        )),
        ("list_files_with_limit", lambda: resp[5]["ok"] is True),
        ("search_text_found", lambda: (
            resp[6]["ok"] is True and resp[6]["data"]["count"] > 0
        )),
        ("search_text_not_found", lambda: (
            resp[7]["ok"] is True and resp[7]["data"]["count"] == 0
        )),
        ("search_text_with_path", lambda: resp[8]["ok"] is True),
        ("search_text_with_limit", lambda: resp[9]["ok"] is True),
        ("create_file_new", lambda: (
            resp[10]["ok"] is True
        )),
        ("create_file_verify_content", lambda: (
            resp[11]["ok"] is True
            and "temp()" in resp[11]["data"]["content"]
        )),
        ("create_file_exists_no_overwrite", lambda: (
            resp[12]["ok"] is False
        )),
        ("create_file_nested_dirs", lambda: resp[13]["ok"] is True),
    ]

    for name, check in tests:
        try:
            assert check(), f"Check failed"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    # Track created files for cleanup
    if resp[10].get("ok"):
        CREATED_FILES.append("src/temp_test.cj")
    if resp[13].get("ok"):
        CREATED_FILES.append("src/sub/nested.cj")

    return results
