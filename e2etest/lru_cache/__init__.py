"""lru_cache: LRU Cache 多 bug 修复。

提供一个有多个 bug 的 LRU Cache 实现（双向链表 + 字典），
让模型定位链表操作和缓存淘汰逻辑中的问题并修复。
覆盖 read_file + run_bash + edit_file 复合调用链。

服务商和模型通过 run_all.py 的 --provider/--model 参数指定。
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from ..driver import CoderProc, Sandbox, get_default_model

NAME = "lru_cache"
TAGS = ["live"]

DATA_DIR = Path(__file__).resolve().parent / "data"


def _read_data(name: str) -> str:
    return (DATA_DIR / name).read_text(encoding="utf-8")


def run(provider: str = "kimi", model: str | None = None) -> tuple[bool, str, str, str]:
    """使用指定服务商和模型修复 LRU Cache 中的多个 bug。"""
    model = model or get_default_model(provider)
    sb = Sandbox.create()
    try:
        sb.write_bootstrap_config(provider)

        # 种入带 bug 的 LRU Cache 项目
        (sb.cwd / "lru_cache.py").write_text(
            _read_data("lru_cache.py"), encoding="utf-8", newline="\n"
        )
        (sb.cwd / "test_lru_cache.py").write_text(
            _read_data("test_lru_cache.py"), encoding="utf-8", newline="\n"
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

            # 验证工具调用
            if "edit_file  {" not in stdout and "write_file  {" not in stdout:
                return False, stdout, stderr, "no edit_file/write_file tool call"
            if "run_bash  {" not in stdout:
                return False, stdout, stderr, "no run_bash call"

            # 独立运行测试确认修复
            result = subprocess.run(
                [sys.executable, "-X", "utf8", "-c",
                 "import sys, runpy; sys.path.insert(0, '.'); "
                 "runpy.run_path(sys.argv[1], run_name='__main__')",
                 "test_lru_cache.py"],
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
                    f"LRU cache tests still failing:\n{result.stdout}\n{result.stderr}"
                )

            # 验证核心结构未被破坏
            src = (sb.cwd / "lru_cache.py").read_text(encoding="utf-8")
            if "class LRUCache" not in src:
                return False, stdout, stderr, "LRUCache class was removed"
            if "_move_to_head" not in src:
                return False, stdout, stderr, "_move_to_head was removed (core structure broken)"

            return True, stdout, stderr, ""
        finally:
            cp.close()
    finally:
        sb.cleanup()
