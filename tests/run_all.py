#!/usr/bin/env python3
"""CangjieCoder MCP Service Test Runner

Runs all MCP tool tests through batch service sessions.  Each test
module queues its tool calls and executes them in one or more
service sessions.

Usage:
    python run_all.py [--bin PATH] [--workspace PATH]

Environment variables:
    SERVICE_BIN     Path to the built cangjiecoder binary
    WORKSPACE_PATH  Path to the test workspace (default: tests/cangjie)

Prerequisites:
    Build the service first: cjpm build
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mcp_client import McpClient  # noqa: E402
import test_skills  # noqa: E402
import test_skills_enhanced  # noqa: E402
import test_workspace_files  # noqa: E402
import test_workspace_edit  # noqa: E402
import test_workspace_commands  # noqa: E402
import test_ast  # noqa: E402
import test_ast_enhanced  # noqa: E402
import test_lsp  # noqa: E402
import test_project  # noqa: E402

TEST_MODULES = [
    ("Skills Search", test_skills),
    ("Skills Enhanced", test_skills_enhanced),
    ("Workspace Files", test_workspace_files),
    ("Workspace Commands", test_workspace_commands),
    ("AST Analysis", test_ast),
    ("AST Enhanced", test_ast_enhanced),
    ("LSP Integration", test_lsp),
    ("Project Templates", test_project),
    ("Workspace Edit & Rollback", test_workspace_edit),
]


def main():
    parser = argparse.ArgumentParser(description="Run MCP service tests")
    parser.add_argument("--bin", help="Path to cangjiecoder binary")
    parser.add_argument("--workspace", help="Path to test workspace")
    args = parser.parse_args()

    print("=" * 60)
    print("CangjieCoder MCP Service Test Suite")
    print("=" * 60)

    def client_factory():
        return McpClient(workspace=args.workspace, service_bin=args.bin)

    # Verify the binary exists
    try:
        c = client_factory()
        c._ensure_binary()
    except FileNotFoundError as e:
        print(f"\nERROR: {e}")
        sys.exit(1)

    # List available tools
    c = client_factory()
    c.start()
    c.list_tools()
    tool_results = c.execute()
    if tool_results:
        tool_count = len(tool_results[0].get("tools", []))
        print(f"\n  Available tools: {tool_count}")
    print()

    total_passed = 0
    total_failed = 0
    all_failures = []

    for section_name, module in TEST_MODULES:
        print(f"--- {section_name} ---")
        results = module.run_tests(client_factory)
        for name, passed, error in results:
            if passed:
                print(f"  \u2713 {name}")
                total_passed += 1
            else:
                print(f"  \u2717 {name}: {error}")
                total_failed += 1
                all_failures.append((section_name, name, error))
        print()

    # Clean up created files
    if hasattr(test_workspace_files, "cleanup_created_files"):
        test_workspace_files.cleanup_created_files()
        print("  Cleaned up test-created files\n")

    # Summary
    print("=" * 60)
    total = total_passed + total_failed
    print(f"Results: {total_passed} passed, {total_failed} failed, "
          f"{total} total")
    if all_failures:
        print("\nFailures:")
        for section, name, error in all_failures:
            print(f"  [{section}] {name}: {error}")
    print("=" * 60)

    sys.exit(0 if total_failed == 0 else 1)


if __name__ == "__main__":
    main()
