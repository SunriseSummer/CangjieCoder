#!/usr/bin/env python3
"""
端到端测试运行入口：自动发现并运行所有测试用例，按用例保存日志到独立子目录，
并自动与上次日志对比，检查是否有退化。

用法：
    cd coder
    python3 e2etest/run_all.py                        # 运行全部测试
    python3 e2etest/run_all.py --mock-only             # 仅运行 mock 测试
    python3 e2etest/run_all.py --skip bug_fix          # 跳过指定测试
    python3 e2etest/run_all.py --only bug_fix              # 仅运行指定测试
    python3 e2etest/run_all.py --cangjie                   # 包含仓颁 AI Coding 测试
    python3 e2etest/run_all.py --provider zhipu --model glm-5.1  # 指定服务商和模型

每个测试用例放在 e2etest/<name>/ 独立目录，包含 __init__.py（导出 run/NAME/TAGS）
和历史 *.log 日志文件。日志默认不删除，可用 clean_logs.py 一键清理。

测试分类（通过 TAGS）：
  - mock    : 基于本地 mock 服务，无需网络和 API Key
  - live    : 需要真实服务商 API Key 和网络连接
  - cangjie : 需要 Cangjie SDK（cjpm 可用），通过 --cangjie 启用
"""

from __future__ import annotations

import importlib
import sys
import time
import traceback
from pathlib import Path

# 把 coder 目录加到 sys.path，以便引用 e2etest 包
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from e2etest.driver import PROVIDER_ENV_KEYS, PROVIDER_DEFAULT_MODELS, get_api_key
from e2etest.log_utils import (
    save_log,
    find_previous_log,
    compare_logs,
    format_log_content,
)


# ═══════════════════════════════════════════════════════════════════
# 测试用例注册表（按执行顺序）
# ═══════════════════════════════════════════════════════════════════

# 每个条目是 (模块名, 对应 e2etest/<name>/ 目录)
# 导入时 e2etest.<name> 即可获取 run(), NAME, TAGS
TEST_MODULES = [
    # mock tests
    "help_exit",
    "agent_write",
    "diff_undo",
    "compact",
    # live tests（需要真实服务商 API，通过 --provider/--model 指定）
    "create_project",
    "bug_fix",
    "lru_cache",
    # Cangjie AI Coding tests (individually controllable)
    "cangjie.json_parser",
    "cangjie.new_project_small",
    "cangjie.new_project_large",
    "cangjie.incremental_dev",
    "cangjie.bug_fix",
]


def _load_test(name: str):
    """动态导入测试模块，返回模块对象。"""
    return importlib.import_module(f"e2etest.{name}")


def _count_iterations(stdout: str) -> int:
    """统计 stdout 中模型交互迭代次数（[tool-call] 或 [final] 出现次数之和）。"""
    return stdout.count("[tool-call]") + stdout.count("[final]")


def run_test(name: str, func, verbose: bool = True) -> bool:
    """运行单个测试，保存日志，与上次对比。返回是否通过。"""
    print(f"\n{'─' * 60}")
    print(f"▶ {name}")
    print(f"{'─' * 60}")

    start = time.monotonic()
    try:
        passed, stdout, stderr, error_msg = func()
    except Exception as e:
        elapsed = time.monotonic() - start
        error_msg = f"{type(e).__name__}: {e}\n{traceback.format_exc()}"
        passed = False
        stdout = ""
        stderr = error_msg
    else:
        elapsed = time.monotonic() - start

    iterations = _count_iterations(stdout)

    # 保存日志
    log_content = format_log_content(
        test_name=name,
        stdout=stdout,
        stderr=stderr,
        duration_secs=elapsed,
        passed=passed,
        error_msg=error_msg if not passed else "",
        iterations=iterations,
    )
    log_path = save_log(name, log_content)
    status = "✅ PASS" if passed else "❌ FAIL"
    print(f"  {status}  ({elapsed:.1f}s, {iterations} 次迭代)  → {log_path.relative_to(log_path.parent.parent)}")
    if not passed and error_msg:
        print(f"  错误: {error_msg[:200]}")

    # 与上次日志对比
    prev_log = find_previous_log(name, log_path)
    if prev_log:
        prev_content = prev_log.read_text(encoding="utf-8")
        issues, info = compare_logs(log_content, prev_content)
        if info:
            print(f"  📊 与上次 ({prev_log.name}) 数据对比:")
            for item in info:
                print(f"    - {item}")
        if issues:
            print(f"  ⚠ 与上次日志 ({prev_log.name}) 对比发现问题:")
            for issue in issues:
                print(f"    - {issue}")
        elif not info:
            print(f"  ✓ 与上次日志 ({prev_log.name}) 对比：无明显退化")
        else:
            print(f"  ✓ 无明显退化")
    else:
        print(f"  (首次运行，无历史日志可对比)")

    return passed


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(
        description="运行端到端测试并保存日志",
        epilog=(
            "示例:\n"
            "  python3 e2etest/run_all.py --mock-only\n"
            "  python3 e2etest/run_all.py --provider zhipu --model glm-5.1\n"
            "  python3 e2etest/run_all.py --provider deepseek"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--mock-only", action="store_true",
                        help="仅运行 mock 测试（无需网络和 API Key）")
    parser.add_argument("--cangjie", action="store_true",
                        help="包含仓颁语言 AI Coding 测试（需 Cangjie SDK）")
    parser.add_argument("--provider", default="kimi",
                        choices=list(PROVIDER_ENV_KEYS.keys()),
                        help="Live 测试使用的服务商（默认: kimi）")
    parser.add_argument("--model", default=None,
                        help="Live 测试使用的模型（默认: 服务商默认模型）")
    parser.add_argument("--skip", nargs="*", default=[], metavar="NAME",
                        help="跳过指定测试用例（如 --skip lru_cache bug_fix）")
    parser.add_argument("--only", nargs="*", default=[], metavar="NAME",
                        help="仅运行指定测试用例（如 --only bug_fix lru_cache）")
    args = parser.parse_args()

    provider = args.provider
    model = args.model or PROVIDER_DEFAULT_MODELS.get(provider, "")

    print("=" * 60)
    print("Cangjie Coder · 端到端测试")
    print("=" * 60)

    # 检查 live 测试所需的 API Key 和网络
    api_key = get_api_key(provider)
    live_available = False
    if not args.mock_only:
        if not api_key:
            env_key = PROVIDER_ENV_KEYS.get(provider, "???")
            print(f"\n⚠ {env_key} 未设置，跳过需要 {provider} API 的 live 测试。")
        else:
            live_available = True
            print(f"\n服务商: {provider}，模型: {model}")

    # 构建运行列表
    skip_set = set(args.skip)
    only_set = set(args.only) if args.only else None
    tests_to_run = []

    for mod_name in TEST_MODULES:
        mod = _load_test(mod_name)
        tags = getattr(mod, "TAGS", [])
        display_name = getattr(mod, "NAME", mod_name)
        run_func = mod.run

        # 过滤逻辑
        if display_name in skip_set:
            print(f"  ⏭ 跳过: {display_name}（--skip）")
            continue
        if only_set and display_name not in only_set:
            continue
        if args.mock_only and "mock" not in tags:
            continue
        if "live" in tags and not live_available:
            continue
        if "cangjie" in tags and not args.cangjie:
            continue

        tests_to_run.append((display_name, run_func, tags))

    if not tests_to_run:
        print("\n没有可运行的测试用例。")
        return

    results = {}
    for name, func, tags in tests_to_run:
        if "live" in tags:
            # live 测试：传入服务商和模型参数
            results[name] = run_test(
                name, lambda f=func: f(provider=provider, model=model)
            )
        else:
            results[name] = run_test(name, func)

    # 汇总
    print(f"\n{'=' * 60}")
    print("测试汇总")
    print(f"{'=' * 60}")
    total = len(results)
    passed = sum(1 for v in results.values() if v)
    failed = total - passed
    for name, ok in results.items():
        print(f"  {'✅' if ok else '❌'} {name}")
    print(f"\n总计: {total} 个测试, {passed} 通过, {failed} 失败")

    if failed > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
