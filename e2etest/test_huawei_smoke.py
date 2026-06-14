#!/usr/bin/env python3
"""
华为云 MaaS 真实模型烟雾测试。

默认 skip。设置环境变量 HUAWEI_API_KEY 后启用：

    export HUAWEI_API_KEY=...
    python3 -m unittest -v e2etest.test_huawei_smoke

烟雾任务有意保持最小：让模型基于一个小型源码场景使用 `write_file` 工具
落盘一个 Python "Hello world"。任务文本与系统提示均明确地引导模型走
tool-calling 路径，避免被模型用纯文本「答复」。

运行环境网络受限或华为云不可达时，整个测试会被自动 skip 而非 fail。
"""

from __future__ import annotations

import os
import socket
import unittest

from .driver import CoderProc, Sandbox


HUAWEI_HOST = "api.modelarts-maas.com"


def _dns_reachable(host: str, timeout: float = 3.0) -> bool:
    try:
        socket.setdefaulttimeout(timeout)
        socket.gethostbyname(host)
        return True
    except Exception:
        return False


@unittest.skipUnless(os.environ.get("HUAWEI_API_KEY"),
                     "HUAWEI_API_KEY not set; skipping live smoke test")
@unittest.skipUnless(_dns_reachable(HUAWEI_HOST),
                     f"{HUAWEI_HOST} not resolvable; skipping live smoke test")
class HuaweiSmokeTests(unittest.TestCase):
    """对真实华为云 MaaS 走一次端到端的工具调用任务。"""

    def _run_task(self, model: str) -> None:
        prompt = (
            "请使用 write_file 工具，在当前目录创建 hello.py，"
            "内容是单行 Python：print('hello from cangjie coder')。"
            "完成后简短回复『done』。"
        )
        sb = Sandbox.create()
        try:
            sb.write_bootstrap_config("huawei")
            cp = CoderProc(sb, startup_timeout=20.0)
            try:
                cp.connect_provider("huawei", model)
                cp.send("/approve auto")
                cp.wait_for("审批策略已设为", timeout=5.0)
                cp.send(prompt)
                ok = cp.wait_for("[final]", timeout=90.0)
                stdout = cp.stdout()
                stderr = cp.stderr()
                if not ok:
                    self.fail(
                        f"[{model}] no [final] within 90s.\n"
                        f"STDOUT:\n{stdout}\nSTDERR:\n{stderr}"
                    )
                target = sb.cwd / "hello.py"
                self.assertTrue(
                    target.exists(),
                    f"[{model}] hello.py not created.\nSTDOUT:\n{stdout}"
                )
                self.assertIn("hello from cangjie coder",
                              target.read_text(encoding="utf-8"))
                self.assertIn("write_file  {", stdout)
            finally:
                cp.close()
        finally:
            sb.cleanup()

    def test_kimi_k2_writes_file(self):
        self._run_task("kimi-k2.6")

    def test_deepseek_v4_writes_file(self):
        self._run_task("deepseek-v4-pro")

    def test_glm_5_1_writes_file(self):
        self._run_task("glm-5.1")


if __name__ == "__main__":
    unittest.main()
