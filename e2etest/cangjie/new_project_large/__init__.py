"""cangjie/new_project_large: 从零创建大型仓颉项目。"""

from __future__ import annotations

from pathlib import Path

from ..helpers import (
    cjpm_build,
    create_cangjie_sandbox,
    create_coder_proc,
    read_data_file,
)
from ...driver import get_default_model

NAME = "cangjie/new_project_large"
TAGS = ["cangjie", "live"]

DATA_DIR = Path(__file__).resolve().parent / "data"


def run(provider: str = "kimi", model: str | None = None) -> tuple[bool, str, str, str]:
    """创建一个多模块数据结构与算法仓颉项目。"""
    model = model or get_default_model(provider)
    task_md = read_data_file(DATA_DIR, "task_data_structures.md")

    sb = create_cangjie_sandbox(provider)
    try:
        cp = create_coder_proc(sb, provider=provider, model=model)
        try:
            cp.send("/approve auto")
            cp.wait_for("审批策略已设为", timeout=5.0)
            cp.send(task_md)
            ok = cp.wait_for("[final]", timeout=900.0)
            stdout, stderr = cp.stdout(), cp.stderr()
            if not ok:
                return False, stdout, stderr, "no [final] within 900s"
            if not (sb.cwd / "cjpm.toml").exists():
                return False, stdout, stderr, "cjpm.toml not created"
            cj_files = list(sb.cwd.rglob("*.cj"))
            if not cj_files:
                return False, stdout, stderr, "no .cj files created"
            all_src = "\n".join(p.read_text(encoding="utf-8") for p in cj_files)
            for name in ["push", "pop", "enqueue", "dequeue", "bubbleSort", "binarySearch"]:
                if name not in all_src:
                    return False, stdout, stderr, f"'{name}' not found in any source file"
            if "write_file  {" not in stdout:
                return False, stdout, stderr, "no write_file calls"
            if "run_bash  {" not in stdout:
                return False, stdout, stderr, "no run_bash calls"
            total_lines = sum(len(p.read_text(encoding="utf-8").splitlines()) for p in cj_files)
            if total_lines <= 80:
                return False, stdout, stderr, f"total lines ({total_lines}) too few for a data structures library"
            passed, build_output = cjpm_build(sb)
            if not passed:
                return False, stdout, stderr, f"cjpm build failed:\n{build_output[-2000:]}"
            return True, stdout, stderr, ""
        finally:
            cp.close()
    finally:
        sb.cleanup()
