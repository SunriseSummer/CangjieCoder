"""help_exit: /help + /exit 基础启动退出测试（mock，无需网络）。"""

from __future__ import annotations

import json

from ..driver import CoderProc, ScriptedReply, mock_server, sandbox

NAME = "help_exit"
TAGS = ["mock"]


def run() -> tuple[bool, str, str, str]:
    """/help 输出帮助 → /exit 正常退出。"""
    with mock_server() as ms, sandbox() as sb:
        sb.write_config(ms.endpoint(), "deepseek-v4-pro", "k")
        cp = CoderProc(sb)
        try:
            cp.send("/help")
            ok1 = cp.wait_for("/diff", timeout=5.0)
            ok2 = cp.wait_for("/undo", timeout=2.0)
            ok3 = cp.wait_for("/compact", timeout=2.0)
            if not all([ok1, ok2, ok3]):
                return False, cp.stdout(), cp.stderr(), "help 输出缺少 /diff /undo /compact"
        finally:
            code = cp.close()
        if code != 0:
            return False, cp.stdout(), cp.stderr(), f"exit code = {code}"
        return True, cp.stdout(), cp.stderr(), ""
