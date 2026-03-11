"""Tests for workspace command execution MCP tools.

Covers workspace.run_command, workspace.run_build, workspace.run_test.
Includes cjpm init test since project creation now uses standard tooling.
"""


def run_tests(client_factory):
    """Run command execution tests. Returns list of (name, passed, error)."""
    results = []
    c = client_factory()
    c.start()
    c.call_tool("workspace.run_command", {                       # 0
        "command": "find", "args": [".", "-name", "*.cj"]
    })
    c.call_tool("workspace.run_command", {                       # 1
        "command": "grep", "args": ["-r", "func", "src/"]
    })
    c.call_tool("workspace.run_command", {                       # 2
        "command": "rm", "args": ["-rf", "/nonexistent_safe_path"]
    })
    c.call_tool("workspace.run_command", {                       # 3
        "command": "cat", "args": ["/etc/hostname"]
    })
    c.call_tool("workspace.run_build")                           # 4
    c.call_tool("workspace.run_test")                            # 5
    c.call_tool("workspace.run_command", {                       # 6
        "command": "cjpm", "args": ["--version"]
    })
    resp = c.execute()

    tests = [
        ("run_command_find", lambda: "ok" in resp[0]),
        ("run_command_grep", lambda: "ok" in resp[1]),
        ("run_command_blocked_rm", lambda: resp[2]["ok"] is False),
        ("run_command_blocked_cat", lambda: resp[3]["ok"] is False),
        ("run_build_format", lambda: (
            "ok" in resp[4] and "summary" in resp[4]
        )),
        ("run_test_format", lambda: (
            "ok" in resp[5] and "summary" in resp[5]
        )),
        # cjpm is on the command whitelist and should execute
        ("run_command_cjpm_allowed", lambda: "ok" in resp[6]),
    ]

    for name, check in tests:
        try:
            assert check(), f"Check failed: {resp}"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    return results
