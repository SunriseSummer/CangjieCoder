"""bug_fix: 多文件 Python 项目多 bug 修复。

提供一个包含多个 bug 的数据处理项目（processor.py + test_processor.py），
让模型读取代码、运行测试、定位多个 bug 并逐一修复。
覆盖 read_file + run_bash + edit_file 复合调用链。

服务商和模型通过 run_all.py 的 --provider/--model 参数指定。
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from ..driver import CoderProc, Sandbox, get_default_model

NAME = "bug_fix"
TAGS = ["live"]

DATA_DIR = Path(__file__).resolve().parent / "data"


def _read_data(name: str) -> str:
    return (DATA_DIR / name).read_text(encoding="utf-8")


def run(provider: str = "kimi", model: str | None = None) -> tuple[bool, str, str, str]:
    """种入多 bug 项目，让模型诊断并修复。"""
    model = model or get_default_model(provider)
    sb = Sandbox.create()
    try:
        sb.write_bootstrap_config(provider)

        # 种入带 bug 的项目文件
        (sb.cwd / "processor.py").write_text(_read_data("processor.py"), encoding="utf-8", newline="\n")
        (sb.cwd / "test_processor.py").write_text(
            _read_data("test_processor.py"), encoding="utf-8", newline="\n"
        )
        task = _read_data("task.md")

        cp = CoderProc(
            sb,
            startup_timeout=20.0,
        )
        try:
            # 通过 /connect 和 /model 命令设置服务商和模型
            cp.connect_provider(provider, model)
            cp.send("/approve auto")
            cp.wait_for("审批策略已设为", timeout=5.0)
            cp.send(task)
            ok = cp.wait_for("[final]", timeout=300.0)
            stdout, stderr = cp.stdout(), cp.stderr()
            if not ok:
                return False, stdout, stderr, "no [final] within 300s"

            # 验证 edit_file 被调用（应多次编辑修复 bug）
            if "edit_file  {" not in stdout and "write_file  {" not in stdout:
                return False, stdout, stderr, "no edit_file/write_file tool call"

            # 验证 run_bash 被调用（运行测试诊断）
            if "run_bash  {" not in stdout:
                return False, stdout, stderr, "no run_bash call (should run tests)"

            # 独立运行测试确认所有 bug 已修复
            result = subprocess.run(
                [sys.executable, "-X", "utf8", "-c",
                 "import sys, runpy; sys.path.insert(0, '.'); "
                 "runpy.run_path(sys.argv[1], run_name='__main__')",
                 "test_processor.py"],
                cwd=str(sb.cwd),
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=30,
            )
            if result.returncode != 0:
                return (
                    False, stdout, stderr,
                    f"tests still failing after fix:\n{result.stdout}\n{result.stderr}"
                )

            # 验证具体 bug 修复
            src = (sb.cwd / "processor.py").read_text(encoding="utf-8")

            # flatten 应该递归展开
            if "flatten" not in src:
                return False, stdout, stderr, "flatten function was removed"

            # deduplicate 逻辑应该修复（not in seen）
            if "deduplicate" not in src:
                return False, stdout, stderr, "deduplicate function was removed"

            return True, stdout, stderr, ""
        finally:
            cp.close()
    finally:
        sb.cleanup()
