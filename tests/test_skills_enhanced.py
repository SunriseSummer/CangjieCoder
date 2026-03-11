"""Tests for enhanced skills MCP tools: skills.batch_search, skills.prompt_context.

Covers real-world scenarios where an AI agent needs to:
- Look up multiple Cangjie language features in one request
- Generate ready-to-use prompt context for code generation
- Efficiently query skill documentation to reduce Token consumption
"""


def run_tests(client_factory):
    """Run enhanced skills tool tests. Returns list of (name, passed, error)."""
    results = []

    # ── Session 1: batch_search scenarios ────────────────────
    c = client_factory()
    c.start()
    # Batch search with multiple Chinese queries
    c.call_tool("skills.batch_search", {                             # 0
        "queries": ["HTTP 服务端", "JSON 解析", "错误处理"]
    })
    # Batch search with English keywords
    c.call_tool("skills.batch_search", {                             # 1
        "queries": ["generic", "class", "interface"]
    })
    # Batch search with single query
    c.call_tool("skills.batch_search", {                             # 2
        "queries": ["泛型约束"]
    })
    # Batch search with empty array should fail
    c.call_tool("skills.batch_search", {                             # 3
        "queries": []
    })
    # Batch search with mixed Chinese/English queries
    c.call_tool("skills.batch_search", {                             # 4
        "queries": ["string 操作", "hashmap", "并发 concurrency"]
    })
    resp = c.execute()

    tests_s1 = [
        # Multi-query batch search should succeed
        ("batch_search_chinese_multi", lambda: (
            resp[0]["ok"] is True
            and resp[0]["data"]["queryCount"] == 3
            and isinstance(resp[0]["data"]["results"], list)
            and len(resp[0]["data"]["results"]) == 3
        )),
        # Each batch result should have query and matches fields
        ("batch_search_result_format", lambda: (
            resp[0]["ok"] is True
            and all(
                "query" in r and "matches" in r
                for r in resp[0]["data"]["results"]
            )
        )),
        # HTTP query should find http-related skills
        ("batch_search_http_relevance", lambda: (
            resp[0]["ok"] is True
            and any(
                "http" in m.get("id", "")
                for r in resp[0]["data"]["results"]
                if "HTTP" in r.get("query", "") or "http" in r.get("query", "").lower()
                for m in r.get("matches", [])
            )
        )),
        # English keyword batch should succeed
        ("batch_search_english", lambda: (
            resp[1]["ok"] is True
            and resp[1]["data"]["queryCount"] == 3
        )),
        # Single query batch should work
        ("batch_search_single", lambda: (
            resp[2]["ok"] is True
            and resp[2]["data"]["queryCount"] == 1
            and len(resp[2]["data"]["results"]) == 1
        )),
        # Empty queries array should fail gracefully
        ("batch_search_empty_queries", lambda: resp[3]["ok"] is False),
        # Mixed language batch should succeed
        ("batch_search_mixed_lang", lambda: (
            resp[4]["ok"] is True
            and resp[4]["data"]["queryCount"] == 3
        )),
    ]
    for name, check in tests_s1:
        try:
            assert check(), "Check failed"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    # ── Session 2: prompt_context scenarios ──────────────────
    c2 = client_factory()
    c2.start()
    # Generate context for HTTP server development
    c2.call_tool("skills.prompt_context", {                          # 0
        "query": "HTTP 服务端",
        "limit": 2
    })
    # Generate context for error handling
    c2.call_tool("skills.prompt_context", {                          # 1
        "query": "错误处理 异常"
    })
    # Context with default limit
    c2.call_tool("skills.prompt_context", {                          # 2
        "query": "generic"
    })
    # Context for unmatched query
    c2.call_tool("skills.prompt_context", {                          # 3
        "query": ""
    })
    # Context with limit=1 should be more compact
    c2.call_tool("skills.prompt_context", {                          # 4
        "query": "class",
        "limit": 1
    })
    # Context with larger limit
    c2.call_tool("skills.prompt_context", {                          # 5
        "query": "class",
        "limit": 5
    })
    resp2 = c2.execute()

    tests_s2 = [
        # HTTP context should have non-empty content
        ("prompt_context_http", lambda: (
            resp2[0]["ok"] is True
            and "data" in resp2[0]
            and "context" in resp2[0]["data"]
        )),
        # Context text should be non-empty for a valid query
        ("prompt_context_http_nonempty", lambda: (
            resp2[0]["ok"] is True
            and len(resp2[0]["data"].get("context", "")) > 0
            and resp2[0]["data"].get("isEmpty") is False
        )),
        # Error handling context
        ("prompt_context_error_handling", lambda: (
            resp2[1]["ok"] is True
            and "context" in resp2[1]["data"]
        )),
        # Generic context
        ("prompt_context_generic", lambda: (
            resp2[2]["ok"] is True
            and "context" in resp2[2]["data"]
        )),
        # Empty query should return all skills context (non-empty)
        ("prompt_context_empty_query", lambda: (
            resp2[3]["ok"] is True
            and "context" in resp2[3]["data"]
        )),
        # limit=1 context should be shorter than limit=5 context
        ("prompt_context_limit_comparison", lambda: (
            resp2[4]["ok"] is True
            and resp2[5]["ok"] is True
            and len(resp2[4]["data"].get("context", ""))
            <= len(resp2[5]["data"].get("context", ""))
        )),
    ]
    for name, check in tests_s2:
        try:
            assert check(), "Check failed"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    # ── Session 3: combined batch + context workflow ─────────
    # Simulates a real AI scenario: batch lookup then generate context
    c3 = client_factory()
    c3.start()
    # Step 1: Batch discover relevant skills for a coding task
    c3.call_tool("skills.batch_search", {                            # 0
        "queries": ["文件读写", "string 处理", "array 操作"]
    })
    # Step 2: Generate context for the most relevant topic
    c3.call_tool("skills.prompt_context", {                          # 1
        "query": "string 处理",
        "limit": 2
    })
    # Step 3: Also use the original search tool
    c3.call_tool("skills.search", {"query": "string"})               # 2
    resp3 = c3.execute()

    tests_s3 = [
        # Batch discovery should find results
        ("workflow_batch_discover", lambda: (
            resp3[0]["ok"] is True
            and resp3[0]["data"]["queryCount"] == 3
        )),
        # Context generation should succeed
        ("workflow_context_gen", lambda: (
            resp3[1]["ok"] is True
            and len(resp3[1]["data"].get("context", "")) > 0
        )),
        # Original search should still work alongside new tools
        ("workflow_original_search", lambda: (
            resp3[2]["ok"] is True
            and len(resp3[2]["data"].get("skills", [])) > 0
        )),
    ]
    for name, check in tests_s3:
        try:
            assert check(), "Check failed"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    # ── Session 4: tools/list includes new skills tools ──────
    c4 = client_factory()
    c4.start()
    c4.list_tools()  # 0
    resp4 = c4.execute()

    tests_s4 = [
        ("tools_list_has_batch_search", lambda: (
            any(t["name"] == "skills.batch_search"
                for t in resp4[0].get("tools", []))
        )),
        ("tools_list_has_prompt_context", lambda: (
            any(t["name"] == "skills.prompt_context"
                for t in resp4[0].get("tools", []))
        )),
        # All new tools should have descriptions
        ("new_tools_have_descriptions", lambda: (
            all(
                len(t.get("description", "")) > 0
                for t in resp4[0].get("tools", [])
                if t["name"] in ("skills.batch_search", "skills.prompt_context",
                                 "cangjie.ast_summary", "cangjie.ast_query_nodes_with_text")
            )
        )),
        # Total tool count should be 24
        ("tools_total_count", lambda: (
            len(resp4[0].get("tools", [])) == 24
        )),
    ]
    for name, check in tests_s4:
        try:
            assert check(), "Check failed"
            results.append((name, True, ""))
        except Exception as e:
            results.append((name, False, str(e)))

    return results
