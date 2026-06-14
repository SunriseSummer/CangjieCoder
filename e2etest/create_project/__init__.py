"""create_project: 多文件 Python 项目创建 + 测试验证。

让模型创建一个包含多个模块和测试的 Python 项目，并运行测试确保正确。
覆盖 write_file（多文件）+ run_bash（执行测试）组合调用链。

服务商和模型通过 run_all.py 的 --provider/--model 参数指定。
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from ..driver import CoderProc, Sandbox, get_default_model

NAME = "create_project"
TAGS = ["live"]

DATA_DIR = Path(__file__).resolve().parent / "data"


def _read_data(name: str) -> str:
    return (DATA_DIR / name).read_text(encoding="utf-8")


def run(provider: str = "kimi", model: str | None = None) -> tuple[bool, str, str, str]:
    """创建多文件 Python 项目并运行测试验证。"""
    model = model or get_default_model(provider)
    task = _read_data("task.md")
    sb = Sandbox.create()
    try:
        sb.write_bootstrap_config(provider)
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

            # 验证核心文件存在
            stats_file = sb.cwd / "stats.py"
            test_file = sb.cwd / "test_stats.py"
            if not stats_file.exists():
                return False, stdout, stderr, "stats.py not created"
            if not test_file.exists():
                return False, stdout, stderr, "test_stats.py not created"

            # 验证 stats.py 包含要求的函数
            stats_src = stats_file.read_text(encoding="utf-8")
            for func_name in ["mean", "median", "stdev"]:
                if f"def {func_name}" not in stats_src:
                    return False, stdout, stderr, f"stats.py missing def {func_name}"

            # 验证 write_file 被调用了多次（至少两个文件）
            if stdout.count("write_file  {") < 2:
                return False, stdout, stderr, "expected multiple write_file calls"

            # 验证 run_bash 被调用（运行测试）
            if "run_bash  {" not in stdout:
                return False, stdout, stderr, "no run_bash call (should run tests)"

            # 独立运行测试确认正确性
            result = subprocess.run(
                [sys.executable, "-X", "utf8", "-c",
                 "import sys, runpy; sys.path.insert(0, '.'); "
                 "runpy.run_path(sys.argv[1], run_name='__main__')",
                 "test_stats.py"],
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
                    f"test_stats.py failed independently:\n{result.stdout}\n{result.stderr}"
                )

            return True, stdout, stderr, ""
        finally:
            cp.close()
    finally:
        sb.cleanup()
