"""cangjie/new_project_small: 从零创建小型仓颉项目。"""

from __future__ import annotations

from pathlib import Path

from ..helpers import (
    cjpm_build,
    create_cangjie_sandbox,
    create_coder_proc,
    read_data_file,
    run_scenarios,
)
from ...driver import get_default_model

NAME = "cangjie/new_project_small"
TAGS = ["cangjie", "live"]

DATA_DIR = Path(__file__).resolve().parent / "data"


def _run_project_scenario(
    label: str, task_file: str, required_names: list[str],
    provider: str = "kimi", model: str | None = None,
) -> tuple[bool, str, str, str]:
    """运行单个新项目场景。"""
    task_md = read_data_file(DATA_DIR, task_file)

    sb = create_cangjie_sandbox(provider)
    try:
        cp = create_coder_proc(sb, provider=provider, model=model)
        try:
            cp.send("/approve auto")
            cp.wait_for("审批策略已设为", timeout=5.0)
            cp.send(task_md)
            ok = cp.wait_for("[final]", timeout=600.0)
            stdout, stderr = cp.stdout(), cp.stderr()
            if not ok:
                return False, stdout, stderr, f"{label}: no [final] within 600s"
            if not (sb.cwd / "cjpm.toml").exists():
                return False, stdout, stderr, f"{label}: cjpm.toml not created"
            cj_files = list(sb.cwd.rglob("*.cj"))
            if not cj_files:
                return False, stdout, stderr, f"{label}: no .cj files created"
            all_src = "\n".join(p.read_text(encoding="utf-8") for p in cj_files)
            for name in required_names:
                if name not in all_src:
                    return False, stdout, stderr, f"{label}: '{name}' not found in source"
            if "write_file  {" not in stdout:
                return False, stdout, stderr, f"{label}: no write_file calls"
            if "run_bash  {" not in stdout:
                return False, stdout, stderr, f"{label}: no run_bash calls"
            passed, build_output = cjpm_build(sb)
            if not passed:
                return False, stdout, stderr, f"{label}: cjpm build failed:\n{build_output[-2000:]}"
            return True, stdout, stderr, ""
        finally:
            cp.close()
    finally:
        sb.cleanup()


def run(provider: str = "kimi", model: str | None = None) -> tuple[bool, str, str, str]:
    """顺序运行两个小型新项目场景。"""
    model = model or get_default_model(provider)
    return run_scenarios([
        ("calculator", lambda: _run_project_scenario(
            "calculator", "task_calculator.md", ["add", "sub", "mul", "div"],
            provider=provider, model=model)),
        ("string_utils", lambda: _run_project_scenario(
            "string_utils", "task_string_utils.md", ["reverseString", "countChar", "isPalindrome"],
            provider=provider, model=model)),
    ])
