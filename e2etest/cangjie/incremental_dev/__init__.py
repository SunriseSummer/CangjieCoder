"""cangjie/incremental_dev: 在已有仓颉项目上做增量开发。"""

from __future__ import annotations

import re
from pathlib import Path

from ..helpers import (
    cjpm_build,
    create_cangjie_sandbox,
    create_coder_proc,
    read_data_file,
    run_scenarios,
    write_cjpm_toml,
)
from ...driver import get_default_model

NAME = "cangjie/incremental_dev"
TAGS = ["cangjie", "live"]

DATA_DIR = Path(__file__).resolve().parent / "data"


def _has_func(source: str, name: str) -> bool:
    """用正则匹配仓颉函数声明。"""
    return re.search(rf"\bfunc\s+{re.escape(name)}\s*\(", source) is not None


def _run_add_function(provider: str = "kimi", model: str | None = None) -> tuple[bool, str, str, str]:
    task_md = read_data_file(DATA_DIR, "task_add_function.md")
    calculator_src = read_data_file(DATA_DIR, "calculator.cj")
    main_src = read_data_file(DATA_DIR, "calculator_main.cj")

    sb = create_cangjie_sandbox(provider)
    try:
        src_dir = sb.cwd / "src"
        src_dir.mkdir(parents=True, exist_ok=True)
        write_cjpm_toml(sb.cwd, "calculator")
        (src_dir / "calculator.cj").write_text(calculator_src, encoding="utf-8")
        (src_dir / "main.cj").write_text(main_src, encoding="utf-8")

        cp = create_coder_proc(sb, provider=provider, model=model)
        try:
            cp.send("/approve auto")
            cp.wait_for("审批策略已设为", timeout=5.0)
            cp.send(task_md)
            ok = cp.wait_for("[final]", timeout=600.0)
            stdout, stderr = cp.stdout(), cp.stderr()
            if not ok:
                return False, stdout, stderr, "add_function: no [final] within 600s"
            calc_src = (src_dir / "calculator.cj").read_text(encoding="utf-8")
            for fn in ["power", "modulo"]:
                if fn not in calc_src:
                    return False, stdout, stderr, f"add_function: {fn} function not added"
            for fn in ["add", "sub", "mul", "div"]:
                if not _has_func(calc_src, fn):
                    return False, stdout, stderr, f"add_function: original func {fn} was removed"
            updated_main = (src_dir / "main.cj").read_text(encoding="utf-8")
            if "power" not in updated_main or "modulo" not in updated_main:
                return False, stdout, stderr, "add_function: new functions not used in main.cj"
            if "edit_file  {" not in stdout:
                return False, stdout, stderr, "add_function: no edit_file calls"
            if "run_bash  {" not in stdout:
                return False, stdout, stderr, "add_function: no run_bash calls"
            passed, build_output = cjpm_build(sb)
            if not passed:
                return False, stdout, stderr, f"add_function: cjpm build failed:\n{build_output[-2000:]}"
            return True, stdout, stderr, ""
        finally:
            cp.close()
    finally:
        sb.cleanup()


def _run_add_module(provider: str = "kimi", model: str | None = None) -> tuple[bool, str, str, str]:
    task_md = read_data_file(DATA_DIR, "task_add_module.md")
    math_utils_src = read_data_file(DATA_DIR, "myproject_math_utils.cj")
    main_src = read_data_file(DATA_DIR, "myproject_main.cj")

    sb = create_cangjie_sandbox(provider)
    try:
        src_dir = sb.cwd / "src"
        src_dir.mkdir(parents=True, exist_ok=True)
        write_cjpm_toml(sb.cwd, "myproject")
        (src_dir / "math_utils.cj").write_text(math_utils_src, encoding="utf-8")
        (src_dir / "main.cj").write_text(main_src, encoding="utf-8")

        cp = create_coder_proc(sb, provider=provider, model=model)
        try:
            cp.send("/approve auto")
            cp.wait_for("审批策略已设为", timeout=5.0)
            cp.send(task_md)
            ok = cp.wait_for("[final]", timeout=600.0)
            stdout, stderr = cp.stdout(), cp.stderr()
            if not ok:
                return False, stdout, stderr, "add_module: no [final] within 600s"
            utils_file = src_dir / "str_utils.cj"
            if not utils_file.exists():
                return False, stdout, stderr, "add_module: str_utils.cj not created"
            utils_src = utils_file.read_text(encoding="utf-8")
            for fn in ["repeatStr", "padLeft", "truncate"]:
                if fn not in utils_src:
                    return False, stdout, stderr, f"add_module: {fn} not found in str_utils.cj"
            math_src = (src_dir / "math_utils.cj").read_text(encoding="utf-8")
            for fn in ["myAbs", "myMax", "myMin"]:
                if not _has_func(math_src, fn):
                    return False, stdout, stderr, f"add_module: original func {fn} was removed"
            updated_main = (src_dir / "main.cj").read_text(encoding="utf-8")
            if not any(name in updated_main for name in ["repeatStr", "padLeft", "truncate"]):
                return False, stdout, stderr, "add_module: new functions not used in main.cj"
            if "write_file  {" not in stdout:
                return False, stdout, stderr, "add_module: no write_file calls"
            if "run_bash  {" not in stdout:
                return False, stdout, stderr, "add_module: no run_bash calls"
            passed, build_output = cjpm_build(sb)
            if not passed:
                return False, stdout, stderr, f"add_module: cjpm build failed:\n{build_output[-2000:]}"
            return True, stdout, stderr, ""
        finally:
            cp.close()
    finally:
        sb.cleanup()


def run(provider: str = "kimi", model: str | None = None) -> tuple[bool, str, str, str]:
    """顺序运行两个增量开发场景。"""
    model = model or get_default_model(provider)
    return run_scenarios([
        ("add_function", lambda: _run_add_function(provider=provider, model=model)),
        ("add_module", lambda: _run_add_module(provider=provider, model=model)),
    ])
