"""Tests for project template MCP tools.

Covers project.list_examples and project.bootstrap_json_parser.
"""


def run_tests(client_factory):
    """Run project template tests. Returns list of (name, passed, error)."""
    results = []
    c = client_factory()
    c.start()
    c.call_tool("project.list_examples")                            # 0
    c.call_tool("project.bootstrap_json_parser", {                  # 1
        "path": "generated/json_parser"
    })
    c.call_tool("project.bootstrap_json_parser", {                  # 2
        "path": "../../outside_workspace"
    })
    c.call_tool("project.bootstrap_json_parser", {"path": ""})      # 3
    resp = c.execute()

    tests = [
        ("list_examples", lambda: (
            "ok" in resp[0] and (not resp[0]["ok"] or "data" in resp[0])
        )),
        ("bootstrap_json_parser", lambda: "ok" in resp[1]),
        ("bootstrap_path_traversal", lambda: "ok" in resp[2]),
        ("bootstrap_empty_path", lambda: "ok" in resp[3]),
    ]

    for name, check in tests:
        try:
            assert check(), "Check failed"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    return results
