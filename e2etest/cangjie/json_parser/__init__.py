"""cangjie/json_parser: 从零实现仓颉语言 JSON Parser（需 Kimi API + Cangjie SDK）。

这是一个较复杂的端到端测试（约 500 行代码），考验模型在 Skills 引导下
进行大规模仓颉语言编码、编译迭代、通过所有测试用例的能力。运行耗时较长
（通常 5-15 分钟），可通过 --skip cangjie/json_parser 跳过。
"""

from __future__ import annotations

import time
from pathlib import Path

from ..helpers import (
    cjpm_test,
    create_cangjie_sandbox,
    create_coder_proc,
    read_data_file,
    write_cjpm_toml,
)
from ...driver import get_default_model

NAME = "cangjie/json_parser"
TAGS = ["cangjie", "live"]

DATA_DIR = Path(__file__).resolve().parent / "data"

_MAIN_CJ = (
    'package json_parser\n'
    '\n'
    'main(): Int64 {\n'
    '    let jsonStr = ##"{"name":"Alice","age":30,"active":true,'
    '"scores":[90,85,95],"address":null}"##\n'
    '    let value = JsonValue.fromString(jsonStr)\n'
    '    println("Parsed JSON:")\n'
    '    println(value.toString())\n'
    '    return 0\n'
    '}\n'
)

MAX_ROUNDS = 3


def run(provider: str = "kimi", model: str | None = None) -> tuple[bool, str, str, str]:
    """给定任务书和测试文件，让模型从零实现 JSON Parser 并通过所有测试。"""
    model = model or get_default_model(provider)
    task_md = read_data_file(DATA_DIR, "json_parser_task.md")
    test_cj = read_data_file(DATA_DIR, "json_parser_test.cj")

    sb = create_cangjie_sandbox(provider)
    try:
        src_dir = sb.cwd / "src"
        src_dir.mkdir(parents=True, exist_ok=True)
        write_cjpm_toml(sb.cwd, "json_parser")
        (src_dir / "json_parser_test.cj").write_text(test_cj, encoding="utf-8")
        (src_dir / "main.cj").write_text(_MAIN_CJ, encoding="utf-8")
        (sb.cwd / "task.md").write_text(task_md, encoding="utf-8")

        cp = create_coder_proc(sb, provider=provider, model=model)
        try:
            cp.send("/approve auto")
            cp.wait_for("审批策略已设为", timeout=5.0)

            cp.send(
                "这个项目要实现一个仓颉语言的 JSON 解析器。"
                "任务书在 task.md，单元测试在 src/json_parser_test.cj，"
                "main.cj 也已给定。"
                "请按 task.md 中的 API 规格，创建 src/json_value.cj 和 "
                "src/json_parser.cj 两个文件实现所有功能。"
                "不要修改已有的 json_parser_test.cj 和 main.cj。"
                "最终目标：cjpm build 编译成功，cjpm test 全部通过。"
                "完成后回复 done。"
            )

            got_final = False
            search_after = cp.stdout_pos()
            for attempt in range(MAX_ROUNDS):
                hit = cp.wait_for_any(
                    ["[final]", "请求失败"],
                    timeout=1500.0,
                    after=search_after,
                )
                if hit is None:
                    break
                new_output = cp.stdout()[search_after:]
                needs_retry = "迭代上限" in new_output or "请求失败" in new_output
                if not needs_retry:
                    got_final = True
                    break
                if attempt < MAX_ROUNDS - 1:
                    time.sleep(1.0)
                    search_after = cp.stdout_pos()
                    cp.send(
                        "请继续完成任务。如果还没有创建 src/json_value.cj 和 "
                        "src/json_parser.cj，请现在创建。"
                        "如果已创建但编译失败，请修复编译错误。"
                        "如果编译通过但测试失败，请修复代码。"
                        "完成后回复 done。"
                    )
                    time.sleep(2.0)

            stdout, stderr = cp.stdout(), cp.stderr()
            if not got_final:
                return False, stdout, stderr, f"no [final] after {MAX_ROUNDS} rounds"

            if not (src_dir / "json_value.cj").exists():
                return False, stdout, stderr, "json_value.cj not created"
            if not (src_dir / "json_parser.cj").exists():
                return False, stdout, stderr, "json_parser.cj not created"

            if "write_file  {" not in stdout:
                return False, stdout, stderr, "no write_file calls"
            if "run_bash  {" not in stdout:
                return False, stdout, stderr, "no run_bash calls"

            coder_passed = "FAILED: 0" in stdout or "jpm test success" in stdout
            if not coder_passed:
                passed, combined = cjpm_test(sb)
                all_pass = (
                    (passed and "jpm test success" in combined)
                    or "FAILED: 0" in combined
                )
                if not all_pass:
                    return False, stdout, stderr, f"cjpm test failed:\n{combined[-2000:]}"

            return True, stdout, stderr, ""
        finally:
            cp.close()
    finally:
        sb.cleanup()
