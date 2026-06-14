"""cangjie/bug_fix: 在已有仓颉项目中定位并修复 bug。"""

from __future__ import annotations

from collections.abc import Callable
from pathlib import Path

from ..helpers import (
    cjpm_run,
    create_cangjie_sandbox,
    create_coder_proc,
    read_data_file,
    run_scenarios,
    write_cjpm_toml,
)
from ...driver import get_default_model

NAME = "cangjie/bug_fix"
TAGS = ["cangjie", "live"]

DATA_DIR = Path(__file__).resolve().parent / "data"


def _run_case(
    label: str,
    project_name: str,
    source_file: str,
    main_file: str,
    task_file: str,
    validator: Callable[[Path], tuple[bool, str]],
    provider: str = "kimi",
    model: str | None = None,
) -> tuple[bool, str, str, str]:
    src_seed = read_data_file(DATA_DIR, source_file)
    main_seed = read_data_file(DATA_DIR, main_file)
    task_md = read_data_file(DATA_DIR, task_file)

    sb = create_cangjie_sandbox(provider)
    try:
        src_dir = sb.cwd / "src"
        src_dir.mkdir(parents=True, exist_ok=True)
        write_cjpm_toml(sb.cwd, project_name)
        (src_dir / source_file).write_text(src_seed, encoding="utf-8")
        (src_dir / "main.cj").write_text(main_seed, encoding="utf-8")

        cp = create_coder_proc(sb, provider=provider, model=model)
        try:
            cp.send("/approve auto")
            cp.wait_for("审批策略已设为", timeout=5.0)
            cp.send(task_md)
            ok = cp.wait_for("[final]", timeout=600.0)
            stdout, stderr = cp.stdout(), cp.stderr()
            if not ok:
                return False, stdout, stderr, f"{label}: no [final] within 600s"
            valid, error_msg = validator(src_dir)
            if not valid:
                return False, stdout, stderr, f"{label}: {error_msg}"
            if "edit_file  {" not in stdout:
                return False, stdout, stderr, f"{label}: no edit_file calls"
            if "run_bash  {" not in stdout:
                return False, stdout, stderr, f"{label}: no run_bash calls"
            passed, run_output = cjpm_run(sb)
            if not passed:
                return False, stdout, stderr, f"{label}: cjpm run failed:\n{run_output[-2000:]}"
            return True, stdout, stderr, ""
        finally:
            cp.close()
    finally:
        sb.cleanup()


def _validate_off_by_one(src_dir: Path) -> tuple[bool, str]:
    src = (src_dir / "math_funcs.cj").read_text(encoding="utf-8")
    if "..=n" not in src:
        return False, "off-by-one bug not fixed in math_funcs.cj"
    if "fibonacci" not in src:
        return False, "fibonacci function was removed"
    main_src = (src_dir / "main.cj").read_text(encoding="utf-8")
    if "f5 != 120" not in main_src:
        return False, "main.cj was unexpectedly modified"
    return True, ""


def _validate_logic_error(src_dir: Path) -> tuple[bool, str]:
    src = (src_dir / "validator.cj").read_text(encoding="utf-8")
    if ">=" not in src:
        return False, "isValidAge >= fix not applied"
    if "||" not in src:
        return False, "isValidScore || fix not applied"
    if "isLeapYear" not in src:
        return False, "isLeapYear function was removed"
    main_src = (src_dir / "main.cj").read_text(encoding="utf-8")
    if "age 0 should be valid" not in main_src:
        return False, "main.cj was unexpectedly modified"
    return True, ""


def _validate_multiple_bugs(src_dir: Path) -> tuple[bool, str]:
    src = (src_dir / "string_ops.cj").read_text(encoding="utf-8")
    if "r'A'" not in src or "r'Z'" not in src:
        return False, "countUpperCase not fixed to uppercase range"
    if "r'0'" not in src:
        return False, "maskDigits not fixed to include 0"
    main_src = (src_dir / "main.cj").read_text(encoding="utf-8")
    if "countUpperCase" not in main_src or "maskDigits" not in main_src:
        return False, "main.cj was unexpectedly modified"
    return True, ""


def run(provider: str = "kimi", model: str | None = None) -> tuple[bool, str, str, str]:
    """顺序运行三个仓颉 bug 修复场景。"""
    model = model or get_default_model(provider)
    return run_scenarios([
        ("fix_off_by_one", lambda: _run_case(
            "fix_off_by_one", "mathfuncs",
            "math_funcs.cj", "math_funcs_main.cj",
            "task_fix_off_by_one.md", _validate_off_by_one,
            provider=provider, model=model)),
        ("fix_logic_error", lambda: _run_case(
            "fix_logic_error", "validator",
            "validator.cj", "validator_main.cj",
            "task_fix_logic_error.md", _validate_logic_error,
            provider=provider, model=model)),
        ("fix_multiple_bugs", lambda: _run_case(
            "fix_multiple_bugs", "stringops",
            "string_ops.cj", "string_ops_main.cj",
            "task_fix_multiple_bugs.md", _validate_multiple_bugs,
            provider=provider, model=model)),
    ])
