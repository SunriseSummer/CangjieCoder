"""Tests for skills.search MCP tool.

Covers basic search, Chinese keywords, English keywords, empty queries,
and specific Cangjie topics.
"""

from mcp_client import McpClient


def run_tests(client_factory):
    """Run skills search tests. Returns list of (name, passed, error)."""
    results = []
    client = client_factory()
    client.start()
    client.call_tool("skills.search", {"query": "函数"})
    client.call_tool("skills.search", {"query": "class"})
    client.call_tool("skills.search", {"query": ""})
    client.call_tool("skills.search", {"query": "泛型约束"})
    client.call_tool("skills.search", {
        "query": "如何在仓颉语言中使用泛型类型参数和约束"
    })
    responses = client.execute()

    tests = [
        ("skills_search_chinese", lambda r: (
            r["ok"] is True and "data" in r
        )),
        ("skills_search_english", lambda r: (
            r["ok"] is True
        )),
        ("skills_search_empty", lambda r: (
            "ok" in r
        )),
        ("skills_search_specific_topic", lambda r: (
            "ok" in r
        )),
        ("skills_search_long_query", lambda r: (
            "ok" in r
        )),
    ]

    for i, (name, check) in enumerate(tests):
        try:
            r = responses[i]
            assert check(r), f"Check failed: {r.get('summary', r)}"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    return results
