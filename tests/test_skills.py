"""Tests for skills.search MCP tool with real Cangjie skill data.

Uses the cangjie-skills-1.0.5 skill set installed in the test
workspace at .github/skills/.  Tests verify skill discovery,
relevance ranking, and content retrieval across common development
scenarios.
"""


def run_tests(client_factory):
    """Run skills search tests. Returns list of (name, passed, error)."""
    results = []
    c = client_factory()
    c.start()
    # ── Typical developer queries ────────────────────────────
    c.call_tool("skills.search", {"query": "类定义和继承"})       # 0
    c.call_tool("skills.search", {"query": "泛型约束"})          # 1
    c.call_tool("skills.search", {"query": "错误处理 异常"})     # 2
    c.call_tool("skills.search", {"query": "HTTP 服务端"})       # 3
    c.call_tool("skills.search", {"query": "单元测试"})          # 4
    c.call_tool("skills.search", {"query": "JSON 解析"})         # 5
    c.call_tool("skills.search", {"query": "文件读写"})          # 6
    # ── Edge cases ───────────────────────────────────────────
    c.call_tool("skills.search", {"query": ""})                  # 7
    c.call_tool("skills.search", {"query": "x" * 500})           # 8
    c.call_tool("skills.search", {
        "query": "如何在仓颉语言中定义一个泛型函数并添加类型约束"
    })                                                           # 9
    resp = c.execute()

    tests = [
        ("skills_class_inheritance", lambda: (
            resp[0]["ok"] is True
            and any("class" in s.get("id", "")
                    for s in resp[0].get("data", {}).get("skills", []))
        )),
        ("skills_generics", lambda: (
            resp[1]["ok"] is True
            and any("generic" in s.get("id", "")
                    for s in resp[1].get("data", {}).get("skills", []))
        )),
        ("skills_error_handling", lambda: (
            resp[2]["ok"] is True
            and any("error" in s.get("id", "")
                    for s in resp[2].get("data", {}).get("skills", []))
        )),
        ("skills_http_server", lambda: (
            resp[3]["ok"] is True
            and any("http" in s.get("id", "")
                    for s in resp[3].get("data", {}).get("skills", []))
        )),
        ("skills_unittest", lambda: (
            resp[4]["ok"] is True
            and any("unittest" in s.get("id", "") or "test" in s.get("id", "")
                    for s in resp[4].get("data", {}).get("skills", []))
        )),
        ("skills_json", lambda: (
            resp[5]["ok"] is True
            and any("json" in s.get("id", "")
                    for s in resp[5].get("data", {}).get("skills", []))
        )),
        ("skills_file_io", lambda: (
            resp[6]["ok"] is True
            and any("fs" in s.get("id", "") or "io" in s.get("id", "")
                    for s in resp[6].get("data", {}).get("skills", []))
        )),
        ("skills_empty_query", lambda: resp[7]["ok"] is True),
        ("skills_very_long_query", lambda: "ok" in resp[8]),
        ("skills_natural_language", lambda: (
            resp[9]["ok"] is True
            and len(resp[9].get("data", {}).get("skills", [])) > 0
        )),
    ]

    for name, check in tests:
        try:
            assert check(), f"Check failed"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    return results
