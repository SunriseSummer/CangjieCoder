"""Tests for workspace.set_root and workspace.get_root MCP tools.

Verifies dynamic workspace root management — the ability to query
and change the workspace root at session level.
"""

import os
import tempfile


def run_tests(client_factory):
    """Run workspace root management tests. Returns list of (name, passed, error)."""
    results = []

    # --- Session 1: workspace.get_root returns default workspace ---
    c1 = client_factory()
    c1.start()
    c1.call_tool("workspace.get_root")                                # 0
    resp1 = c1.execute()

    # --- Session 2: workspace.set_root + workspace.get_root round-trip ---
    tmp_dir = tempfile.mkdtemp(prefix="cjcoder_test_root_")
    c2 = client_factory()
    c2.start()
    c2.call_tool("workspace.set_root", {"path": tmp_dir})             # 0
    c2.call_tool("workspace.get_root")                                # 1
    resp2 = c2.execute()

    # --- Session 3: workspace.set_root validation failures ---
    c3 = client_factory()
    c3.start()
    c3.call_tool("workspace.set_root", {"path": ""})                  # 0: empty
    c3.call_tool("workspace.set_root", {"path": "relative/path"})     # 1: relative
    c3.call_tool("workspace.set_root", {"path": "/nonexistent/abc"})  # 2: doesn't exist
    resp3 = c3.execute()

    tests = [
        # get_root returns a result with workspaceRoot key
        ("get_root_returns_workspace",
         lambda: resp1[0].get("ok") is True and
         "workspaceRoot" in resp1[0].get("data", {})),

        # get_root default workspace is a non-empty string
        ("get_root_default_nonempty",
         lambda: len(resp1[0].get("data", {}).get("workspaceRoot", "")) > 0),

        # set_root with valid directory succeeds
        ("set_root_valid_dir",
         lambda: resp2[0].get("ok") is True),

        # set_root result contains the new root path
        ("set_root_returns_path",
         lambda: tmp_dir in resp2[0].get("data", {}).get("workspaceRoot", "")),

        # get_root after set_root reflects the new root
        ("get_root_after_set",
         lambda: tmp_dir in resp2[1].get("data", {}).get("workspaceRoot", "")),

        # set_root with empty path fails
        ("set_root_empty_fails",
         lambda: resp3[0].get("ok") is False),

        # set_root with relative path fails
        ("set_root_relative_fails",
         lambda: resp3[1].get("ok") is False),

        # set_root with nonexistent path fails
        ("set_root_nonexistent_fails",
         lambda: resp3[2].get("ok") is False),
    ]

    for name, check in tests:
        try:
            assert check(), "Check failed"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    # Clean up
    try:
        os.rmdir(tmp_dir)
    except OSError:
        pass

    return results
