#!/usr/bin/env python3
"""End-to-end test: AI-driven JsonParser project development via MCP tools.

This script replays a simulated AI coding session that develops a complete
JsonParser library in Cangjie — from project scaffolding to passing tests —
using **only** the MCP tool interface exposed by cangjiecoder.

AI-generated code snippets live in separate ``codepieceN.ai`` files so
that the MCP test logic stays clean and readable.  The helper function
``ai_generate()`` wraps file reads to mimic an AI model request, while
``agent_plan()`` / ``agent_analyse()`` print the reasoning an agent would
produce at each decision point.

Usage:
    python tests/e2etest_jsonparser/run.py [--bin PATH] [--keep]
"""

import argparse
import os
import shutil
import sys
import tempfile

# ---------------------------------------------------------------------------
# Bootstrap — locate helpers and shared MCP client
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TESTS_DIR = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, TESTS_DIR)
from mcp_client import McpClient  # noqa: E402

REPO_ROOT = os.path.dirname(TESTS_DIR)
DEFAULT_BIN = os.path.join(REPO_ROOT, "target", "release", "bin", "cangjiecoder")


# ---------------------------------------------------------------------------
# Simulated AI / Agent helpers
# ---------------------------------------------------------------------------

def ai_generate(piece_id, prompt=""):
    """Simulate an AI model request that returns a code snippet.

    In a real agent this would call an LLM API.  Here we read from the
    pre-written ``codepieceN.ai`` file to make the test deterministic
    and reproducible.

    Args:
        piece_id: Integer id that maps to ``codepiece<id>.ai``.
        prompt:   The (simulated) prompt sent to the model — logged for
                  traceability but not actually used.
    Returns:
        The file content as a string.
    """
    path = os.path.join(SCRIPT_DIR, f"codepiece{piece_id}.ai")
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    label = os.path.basename(path)
    print(f"  🤖 AI 生成代码 ← {label}  ({len(content)} bytes)")
    if prompt:
        print(f"     prompt: {prompt[:80]}{'…' if len(prompt) > 80 else ''}")
    return content


def agent_plan(title, details):
    """Print a planning step — mimics the agent's chain-of-thought."""
    print(f"\n  📋 Agent 规划: {title}")
    for line in details:
        print(f"     • {line}")


def agent_analyse(summary):
    """Print an analysis conclusion — mimics agent interpreting tool output."""
    print(f"  🔍 Agent 分析: {summary}")


# ---------------------------------------------------------------------------
# Test orchestration helpers
# ---------------------------------------------------------------------------

def step(msg):
    """Print a phase banner."""
    print(f"\n{'─' * 64}")
    print(f"  🔧  {msg}")
    print(f"{'─' * 64}")


# ---------------------------------------------------------------------------
# Main e2e scenario
# ---------------------------------------------------------------------------

def run_e2e(service_bin, keep_workspace):
    """Execute the full JsonParser development scenario."""

    workspace = tempfile.mkdtemp(prefix="cjcoder_e2e_jsonparser_")
    print(f"\n  Workspace: {workspace}")

    passed = 0
    failed = 0
    errors = []

    def record(ok, name, detail=""):
        nonlocal passed, failed
        if ok:
            print(f"  ✓ {name}")
            passed += 1
        else:
            info = f": {detail}" if detail else ""
            print(f"  ✗ {name}{info}")
            failed += 1
            errors.append(name)

    def client():
        return McpClient(workspace=workspace, service_bin=service_bin)

    try:
        # ==============================================================
        # Phase 1 — Knowledge gathering: search relevant Cangjie skills
        # ==============================================================
        step("Phase 1: Search Cangjie skills for domain knowledge")

        agent_plan("收集领域知识", [
            "搜索 JSON 解析相关 Skill，了解仓颉 JSON 处理方式",
            "搜索 enum / class / 单元测试 Skill，确认语法要点",
            "根据 Skill 结果决定技术方案",
        ])

        c = client()
        c.start()
        c.call_tool("skills.search", {"query": "JSON 解析"})
        c.call_tool("skills.search", {"query": "enum 枚举"})
        c.call_tool("skills.search", {"query": "单元测试 unittest"})
        c.call_tool("skills.search", {"query": "class 类定义"})
        resp = c.execute()

        for i, topic in enumerate(["JSON", "enum", "unittest", "class"]):
            record(resp[i].get("ok") is True, f"skills.search({topic})")

        agent_analyse(
            "Skills 搜索成功：已获取 JSON 处理、枚举定义、单元测试和类定义的参考资料。"
            " 确认：枚举需要 @Derive[Equatable] 才能用 ==；Float64.parse 需要 import std.convert.*"
        )

        # ==============================================================
        # Phase 2 — Project scaffolding: create workspace & source files
        # ==============================================================
        step("Phase 2: Initialize project and create source files")

        agent_plan("项目架构设计", [
            "创建 cjpm.toml 作为项目配置 (executable)",
            "设计分层结构: JsonValue 数据模型 → JsonLexer 词法 → JsonParser 解析 → main 演示",
            "按依赖顺序逐步生成代码，每步请求 AI 生成并写入文件",
        ])

        # --- 2a: project config ---
        cjpm_toml = ai_generate(1, "生成 cjpm.toml: 项目名 jsonparser, 可执行, SDK 1.0.5")

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {
            "path": "cjpm.toml", "content": cjpm_toml
        })
        resp = c.execute()
        record(resp[1].get("ok") is True, "workspace.create_file(cjpm.toml)")

        agent_analyse("项目配置已创建，开始逐步生成源码文件。")

        # --- 2b: data model ---
        json_value_cj = ai_generate(
            2, "生成 JSON 值类型: enum JsonValueKind + class JsonValue, "
               "包含 Null/Bool/Number/String/Array/Object 和 display()"
        )

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {
            "path": "src/json_value.cj", "content": json_value_cj
        })
        resp = c.execute()
        record(resp[1].get("ok") is True, "workspace.create_file(json_value.cj)")

        # --- 2c: lexer ---
        json_lexer_cj = ai_generate(
            3, "生成 JSON 词法分析器: enum TokenKind + class JsonLexer, "
               "基于 Rune 数组逐字符扫描, 处理字符串转义"
        )

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {
            "path": "src/json_lexer.cj", "content": json_lexer_cj
        })
        resp = c.execute()
        record(resp[1].get("ok") is True, "workspace.create_file(json_lexer.cj)")

        # --- 2d: parser ---
        json_parser_cj = ai_generate(
            4, "生成 JSON 递归下降解析器: class JsonParser + ParseResult, "
               "支持 null/bool/number/string/array/object, 便捷入口 parseJson()"
        )

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {
            "path": "src/json_parser.cj", "content": json_parser_cj
        })
        resp = c.execute()
        record(resp[1].get("ok") is True, "workspace.create_file(json_parser.cj)")

        # --- 2e: main entry ---
        main_cj = ai_generate(
            5, "生成 main.cj 演示入口: 解析完整 JSON 对象、嵌套结构、各种基本类型"
        )

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {
            "path": "src/main.cj", "content": main_cj
        })
        resp = c.execute()
        record(resp[1].get("ok") is True, "workspace.create_file(main.cj)")

        agent_analyse("所有源码文件已创建，准备进行 AST 分析验证代码结构。")

        # --- 2f: verify file listing ---
        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.list_files", {"path": "src"})
        resp = c.execute()

        files_ok = resp[1].get("ok") is True
        file_count = resp[1].get("data", {}).get("count", 0) if files_ok else 0
        record(files_ok and file_count >= 4,
               f"workspace.list_files(src): {file_count} files")

        # ==============================================================
        # Phase 3 — Code review: analyse files with AST tools
        # ==============================================================
        step("Phase 3: Analyse created files with AST tools")

        agent_plan("代码结构审查", [
            "用 ast_summary 检查每个文件的顶层定义",
            "用 ast_parse 验证 main.cj 语法正确",
            "用 ast_query_nodes_with_text 列出 parser 的函数签名",
        ])

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("cangjie.ast_summary", {"path": "src/json_value.cj"})
        c.call_tool("cangjie.ast_summary", {"path": "src/json_lexer.cj"})
        c.call_tool("cangjie.ast_summary", {"path": "src/json_parser.cj"})
        c.call_tool("cangjie.ast_parse", {"path": "src/main.cj"})
        c.call_tool("cangjie.ast_query_nodes_with_text", {
            "path": "src/json_parser.cj",
            "nodeType": "functionDefinition"
        })
        resp = c.execute()

        # ast_summary for json_value.cj
        sv_ok = resp[1].get("ok") is True
        sv_entries = resp[1].get("data", {}).get("entries", [])
        record(sv_ok and len(sv_entries) > 0,
               f"ast_summary(json_value.cj): {len(sv_entries)} entries")

        # ast_summary for json_lexer.cj
        record(resp[2].get("ok") is True, "ast_summary(json_lexer.cj)")

        # ast_summary for json_parser.cj
        record(resp[3].get("ok") is True, "ast_summary(json_parser.cj)")

        # ast_parse of main.cj
        pm_sexp = resp[4].get("data", {}).get("sexp", "")
        record(resp[4].get("ok") is True and "mainDefinition" in pm_sexp,
               "ast_parse(main.cj): contains mainDefinition")

        # ast_query functions
        qf_count = resp[5].get("data", {}).get("matchCount", 0) \
            if resp[5].get("ok") else 0
        record(qf_count > 0,
               f"ast_query_nodes_with_text(functionDefinition): {qf_count}")

        agent_analyse(
            f"AST 分析完成: json_value.cj 有 {len(sv_entries)} 个顶层定义,"
            f" json_parser.cj 有 {qf_count} 个函数。代码结构符合预期。"
        )

        # ==============================================================
        # Phase 4 — Content verification: read back & search
        # ==============================================================
        step("Phase 4: Read back key files and verify content")

        agent_plan("内容交叉验证", [
            "读取 cjpm.toml 确认项目名",
            "读取 json_value.cj 确认核心类型",
            "全局搜索 parseJson 确认引用关系",
        ])

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.read_file", {"path": "cjpm.toml"})
        c.call_tool("workspace.read_file", {"path": "src/json_value.cj"})
        c.call_tool("workspace.read_file", {"path": "src/json_parser.cj"})
        c.call_tool("workspace.search_text", {"query": "parseJson"})
        resp = c.execute()

        toml_content = resp[1].get("data", {}).get("content", "")
        record('name = "jsonparser"' in toml_content,
               "cjpm.toml contains correct package name")

        jv_content = resp[2].get("data", {}).get("content", "")
        record("class JsonValue" in jv_content
               and "enum JsonValueKind" in jv_content,
               "json_value.cj has JsonValue class and JsonValueKind enum")

        jp_content = resp[3].get("data", {}).get("content", "")
        record("func parseJson" in jp_content
               and "class JsonParser" in jp_content,
               "json_parser.cj has JsonParser class and parseJson function")

        sr_count = resp[4].get("data", {}).get("count", 0)
        record(resp[4].get("ok") is True and sr_count >= 2,
               f"search_text(parseJson): found in {sr_count} locations")

        agent_analyse("文件内容验证通过，准备首次构建。")

        # ==============================================================
        # Phase 5 — First build attempt
        # ==============================================================
        step("Phase 5: Build the JsonParser project")

        agent_plan("首次构建", [
            "执行 workspace.run_build 编译项目",
            "如果失败则分析错误并修复",
        ])

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.run_build")
        resp = c.execute()

        build_result = resp[1]
        build_ok = build_result.get("ok") is True
        build_exit = build_result.get("data", {}).get("exitCode", -1)
        if build_ok and build_exit == 0:
            record(True, "workspace.run_build succeeded")
            agent_analyse("构建成功，准备添加单元测试。")
        else:
            stderr = build_result.get("data", {}).get("stderr", "")
            stdout = build_result.get("data", {}).get("stdout", "")
            record(False, "workspace.run_build",
                   f"exit={build_exit}\n    stdout: {stdout[:500]}"
                   f"\n    stderr: {stderr[:500]}")

        # ==============================================================
        # Phase 6 — Add tests and run them
        # ==============================================================
        step("Phase 6: Generate unit tests and run them")

        agent_plan("编写单元测试", [
            "请求 AI 生成覆盖全部 JSON 类型的测试文件",
            "写入 src/json_parser_test.cj",
            "执行 workspace.run_test 运行测试",
        ])

        test_cj = ai_generate(
            6, "生成 JsonParser 单元测试: 覆盖 null/bool/number/string/"
               "array/object/嵌套/空白/错误情况/display"
        )

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.create_file", {
            "path": "src/json_parser_test.cj", "content": test_cj
        })
        c.call_tool("workspace.run_test")
        resp = c.execute()

        record(resp[1].get("ok") is True,
               "workspace.create_file(json_parser_test.cj)")

        test_result = resp[2]
        test_ok = test_result.get("ok") is True
        test_exit = test_result.get("data", {}).get("exitCode", -1)
        test_stdout = test_result.get("data", {}).get("stdout", "")
        if test_ok and test_exit == 0:
            record(True, "workspace.run_test succeeded")
            if "Passed" in test_stdout:
                print(f"    {test_stdout.strip()}")
            agent_analyse("所有单元测试通过 ✅")
        else:
            test_stderr = test_result.get("data", {}).get("stderr", "")
            record(False, "workspace.run_test",
                   f"exit={test_exit}\n    stdout: {test_stdout[:500]}"
                   f"\n    stderr: {test_stderr[:500]}")

        # ==============================================================
        # Phase 7 — Post-build verification
        # ==============================================================
        step("Phase 7: Post-build verification with AST analysis")

        agent_plan("最终验证", [
            "AST 分析测试文件，确认测试类存在",
            "查询 json_value.cj 的 enum 定义数量",
            "列出所有文件确认项目完整性",
        ])

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("cangjie.ast_summary", {
            "path": "src/json_parser_test.cj"
        })
        c.call_tool("cangjie.ast_query_nodes", {
            "path": "src/json_value.cj",
            "nodeType": "enumDefinition"
        })
        c.call_tool("workspace.list_files")
        resp = c.execute()

        ts_text = resp[1].get("data", {}).get("summary", "")
        record(resp[1].get("ok") is True and "class" in ts_text.lower(),
               "ast_summary(test file) detected test class")

        eq_count = resp[2].get("data", {}).get("matchCount", 0)
        record(resp[2].get("ok") is True and eq_count >= 1,
               f"ast_query_nodes(enumDefinition): found {eq_count}")

        fl_count = resp[3].get("data", {}).get("count", 0)
        record(resp[3].get("ok") is True and fl_count >= 6,
               f"workspace.list_files: {fl_count} files")

        agent_analyse(
            f"项目完整性验证通过: 测试类已识别, {eq_count} 个枚举定义,"
            f" 共 {fl_count} 个文件。JsonParser 项目开发流程结束。"
        )

    except Exception as e:
        print(f"\n  ✗ FATAL ERROR: {e}")
        failed += 1
        errors.append(f"fatal: {e}")

    finally:
        if keep_workspace:
            print(f"\n  📁 Workspace preserved at: {workspace}")
        else:
            shutil.rmtree(workspace, ignore_errors=True)
            print(f"\n  🗑  Workspace cleaned up")

    return passed, failed, errors


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="E2E test: AI-driven JsonParser project via MCP tools"
    )
    parser.add_argument(
        "--bin", default=DEFAULT_BIN,
        help="Path to cangjiecoder binary"
    )
    parser.add_argument(
        "--keep", action="store_true",
        help="Keep the generated workspace after the test"
    )
    args = parser.parse_args()

    print("=" * 64)
    print("  E2E Test: JsonParser Project Development via MCP Tools")
    print("=" * 64)

    passed, failed, errors = run_e2e(args.bin, args.keep)

    print("\n" + "=" * 64)
    total = passed + failed
    print(f"  Results: {passed} passed, {failed} failed, {total} total")
    if errors:
        print(f"\n  Failures:")
        for e in errors:
            print(f"    • {e}")
    print("=" * 64)

    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
