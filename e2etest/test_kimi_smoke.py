#!/usr/bin/env python3
"""
真实模型端到端冒烟测试：使用 Kimi (Moonshot) 服务商跑 AI Coding 实战任务，
验证整条 agent 链路（HTTPS / tool calling / agent loop / 9 个内置工具 / 审批）。

覆盖场景：
  - test_write_hello_world       — 最小 write_file 链路
  - test_two_file_fibonacci_task — 多文件 write_file + 真实 unittest
  - test_bug_fix_workflow        — run_bash 复现→edit_file 修复→run_bash 验证
  - test_multifile_project_creation — 5+ 文件新建 + run_bash 跑测试
  - test_incremental_development — list_dir→read_file→edit_file→run_bash 增量
  - test_multi_bug_fix_with_grep — grep_search + read_file + edit_file 多 bug 修复
  - test_thinking_model_bug_fix  — kimi-k2.6 思考模型 reasoning_content + bug 修复
  - test_incremental_dev_with_k2_5 — kimi-k2.5 增量开发 div 函数 + 测试

默认 skip。下列任一条件不满足时跳过：
  - 环境变量 KIMI_API_KEY 未设置；
  - api.moonshot.cn 无法解析（网络受限）；
  - 编译产物 ../target/release/bin/main 不存在。

此前 Cangjie 1.0.5 stdx.net.tls 在 Ubuntu 22.04 + api.moonshot.cn 组合
下存在 TLS 问题；现在 buildHttpClient 中的 SNI 修复已完成，
本测试不再需要额外的 TLS 绕过配置。
"""

from __future__ import annotations

import os
import socket
import unittest
from pathlib import Path

from .driver import CoderProc, Sandbox


KIMI_HOST = "api.moonshot.cn"


def _dns_reachable(host: str, timeout: float = 3.0) -> bool:
    try:
        socket.setdefaulttimeout(timeout)
        socket.gethostbyname(host)
        return True
    except Exception:
        return False


@unittest.skipUnless(os.environ.get("KIMI_API_KEY"),
                     "KIMI_API_KEY not set; skipping live smoke test")
@unittest.skipUnless(_dns_reachable(KIMI_HOST),
                     f"{KIMI_HOST} not resolvable; skipping live smoke test")
class KimiSmokeTests(unittest.TestCase):
    """对真实 Moonshot/Kimi 服务跑一次 tool-calling 任务。"""

    def test_write_hello_world(self):
        prompt = (
            "请用 write_file 工具创建文件 hello.py，"
            "内容是单行 print(\"hello from cangjie coder\")。"
            "完成后简短回复 done。"
        )
        sb = Sandbox.create()
        try:
            sb.write_bootstrap_config("kimi")
            cp = CoderProc(
                sb,
                startup_timeout=20.0,
            )
            try:
                cp.connect_provider("kimi", "moonshot-v1-8k")
                cp.send("/approve auto")
                cp.wait_for("审批策略已设为", timeout=5.0)
                cp.send(prompt)
                ok = cp.wait_for("[final]", timeout=90.0)
                stdout = cp.stdout()
                if not ok:
                    self.fail(
                        "no [final] within 90s.\n"
                        f"STDOUT:\n{stdout}\nSTDERR:\n{cp.stderr()}"
                    )
                hello = sb.cwd / "hello.py"
                self.assertTrue(hello.exists(),
                                f"hello.py not created.\nSTDOUT:\n{stdout}")
                content = hello.read_text(encoding="utf-8")
                self.assertIn("hello from cangjie coder", content)
                self.assertIn("write_file  {", stdout)
            finally:
                cp.close()
        finally:
            sb.cleanup()

    def test_two_file_fibonacci_task(self):
        """让模型同时落盘 fib.py 与 test_fib.py，然后用 python 跑通测试。"""
        import subprocess
        prompt = (
            "请用 write_file 创建两个 Python 文件："
            "(1) fib.py，包含 fib(n) 返回第 n 个斐波那契数（n 从 0 开始，"
            "0,1,1,2,3,5,...）；"
            "(2) test_fib.py，使用 unittest 测试 fib(0)==0、fib(1)==1、"
            "fib(6)==8、fib(10)==55。完成后简短回复 done。"
        )
        sb = Sandbox.create()
        try:
            sb.write_bootstrap_config("kimi")
            cp = CoderProc(
                sb,
                startup_timeout=20.0,
            )
            try:
                cp.connect_provider("kimi", "moonshot-v1-8k")
                cp.send("/approve auto")
                cp.wait_for("审批策略已设为", timeout=5.0)
                cp.send(prompt)
                ok = cp.wait_for("[final]", timeout=120.0)
                stdout = cp.stdout()
                if not ok:
                    self.fail(f"no [final] within 120s.\nSTDOUT:\n{stdout}")
                fib = sb.cwd / "fib.py"
                test = sb.cwd / "test_fib.py"
                self.assertTrue(fib.exists(), "fib.py missing")
                self.assertTrue(test.exists(), "test_fib.py missing")
                # 真实运行模型写的测试套件，验证代码可执行且通过
                r = subprocess.run(
                    ["python3", "-m", "unittest", "test_fib"],
                    cwd=str(sb.cwd), capture_output=True, timeout=30,
                )
                self.assertEqual(
                    r.returncode, 0,
                    f"model-written tests failed.\n"
                    f"stdout:{r.stdout!r}\nstderr:{r.stderr!r}\n"
                    f"fib.py:\n{fib.read_text(encoding='utf-8')}\n"
                    f"test_fib.py:\n{test.read_text(encoding='utf-8')}"
                )
            finally:
                cp.close()
        finally:
            sb.cleanup()

    def test_bug_fix_workflow(self):
        """实战 bug fix：种入一处人为 bug，让模型用 run_bash 复现→
        read_file 定位→edit_file 修复→run_bash 验证。"""
        import subprocess
        sb = Sandbox.create()
        try:
            # 种入一个最小可工作的项目，但其中 mul 函数被故意写成减法
            (sb.cwd / "calc").mkdir()
            (sb.cwd / "tests").mkdir()
            (sb.cwd / "calc" / "__init__.py").write_text("", encoding="utf-8")
            (sb.cwd / "calc" / "ops.py").write_text(
                "def add(a, b): return a + b\n"
                "def mul(a, b): return a - b  # BUG: should be *\n",
                encoding="utf-8",
            )
            (sb.cwd / "tests" / "test_ops.py").write_text(
                "import unittest\n"
                "from calc import ops\n"
                "class T(unittest.TestCase):\n"
                "    def test_add(self): self.assertEqual(ops.add(2,3), 5)\n"
                "    def test_mul(self): self.assertEqual(ops.mul(4,3), 12)\n"
                "if __name__=='__main__': unittest.main()\n",
                encoding="utf-8",
            )
            sb.write_bootstrap_config("kimi")
            cp = CoderProc(
                sb,
                startup_timeout=20.0,
            )
            try:
                cp.connect_provider("kimi", "moonshot-v1-8k")
                cp.send("/approve auto")
                cp.wait_for("审批策略已设为", timeout=5.0)
                cp.send(
                    "现在跑 python3 -m unittest discover -s tests 有测试失败。"
                    "请用 run_bash 复现，定位失败的源代码 bug 并修复（不要修改测试用例），"
                    "最终让所有测试通过。完成后回复 done。"
                )
                ok = cp.wait_for("[final]", timeout=180.0)
                stdout = cp.stdout()
                if not ok:
                    self.fail(f"no [final] within 180s.\nSTDOUT:\n{stdout}")
                # 模型应当在源码中把 mul 改回乘法
                fixed = (sb.cwd / "calc" / "ops.py").read_text(encoding="utf-8")
                self.assertIn("a * b", fixed,
                              f"bug not fixed; ops.py is:\n{fixed}")
                # 测试套件不应被改坏
                test_src = (sb.cwd / "tests" / "test_ops.py").read_text(encoding="utf-8")
                self.assertIn("ops.mul(4,3), 12", test_src,
                              "model wrongly modified the test instead of source")
                # 真实运行验证
                r = subprocess.run(
                    ["python3", "-m", "unittest", "discover", "-s", "tests"],
                    cwd=str(sb.cwd), capture_output=True, timeout=30,
                )
                self.assertEqual(r.returncode, 0,
                                 f"tests still failing after fix.\n"
                                 f"stderr:{r.stderr!r}\nops.py:\n{fixed}")
                # 工具序列应当至少包含 run_bash + edit_file
                self.assertIn("run_bash  {", stdout)
                self.assertIn("edit_file  {", stdout)
            finally:
                cp.close()
        finally:
            sb.cleanup()

    def test_multifile_project_creation(self):
        """多文件新项目：让模型用 write_file 创建 calc 包 + 测试，
        再用 run_bash 跑 unittest 验证。触发 write_file + run_bash 组合。"""
        import subprocess
        prompt = (
            "请用 write_file 创建一个 Python 计算器项目："
            "1) calc/__init__.py（空文件）"
            "2) calc/ops.py（包含 add, mul 两个函数）"
            "3) tests/__init__.py（空文件）"
            "4) tests/test_ops.py（用 unittest 测试 add 和 mul 至少各 2 个用例）"
            "落盘后用 run_bash 跑 python3 -m unittest discover -s tests -v。"
            "完成后回复 done。"
        )
        sb = Sandbox.create()
        try:
            sb.write_bootstrap_config("kimi")
            cp = CoderProc(
                sb,
                startup_timeout=20.0,
            )
            try:
                cp.connect_provider("kimi", "kimi-k2-turbo-preview")
                cp.send("/approve auto")
                cp.wait_for("审批策略已设为", timeout=5.0)
                cp.send(prompt)
                ok = cp.wait_for("[final]", timeout=180.0)
                stdout = cp.stdout()
                if not ok:
                    self.fail(
                        f"no [final] within 180s.\n"
                        f"STDOUT:\n{stdout}\nSTDERR:\n{cp.stderr()}"
                    )
                # 验证所有文件被创建
                self.assertTrue((sb.cwd / "calc" / "__init__.py").exists())
                self.assertTrue((sb.cwd / "calc" / "ops.py").exists())
                self.assertTrue((sb.cwd / "tests" / "test_ops.py").exists())
                # 验证工具调用
                self.assertIn("write_file  {", stdout)
                self.assertIn("run_bash  {", stdout)
                # 真实运行测试
                r = subprocess.run(
                    ["python3", "-m", "unittest", "discover", "-s", "tests", "-v"],
                    cwd=str(sb.cwd), capture_output=True, timeout=30,
                )
                self.assertEqual(
                    r.returncode, 0,
                    f"model-written tests failed.\n"
                    f"stderr:{r.stderr!r}\n"
                    f"ops.py:\n{(sb.cwd / 'calc' / 'ops.py').read_text()}"
                )
            finally:
                cp.close()
        finally:
            sb.cleanup()

    def test_incremental_development(self):
        """增量开发：在已有 calc 项目上增加 sub 函数，触发
        list_dir → read_file → edit_file → run_bash 组合工具链。"""
        import subprocess
        sb = Sandbox.create()
        try:
            # 种入已有项目
            (sb.cwd / "calc").mkdir()
            (sb.cwd / "tests").mkdir()
            (sb.cwd / "calc" / "__init__.py").write_text("", encoding="utf-8")
            (sb.cwd / "calc" / "ops.py").write_text(
                "def add(a, b):\n    return a + b\n\n"
                "def mul(a, b):\n    return a * b\n",
                encoding="utf-8",
            )
            (sb.cwd / "tests" / "__init__.py").write_text("", encoding="utf-8")
            (sb.cwd / "tests" / "test_ops.py").write_text(
                "import unittest\n"
                "from calc.ops import add, mul\n\n"
                "class TestOps(unittest.TestCase):\n"
                "    def test_add(self): self.assertEqual(add(2,3), 5)\n"
                "    def test_mul(self): self.assertEqual(mul(4,3), 12)\n\n"
                "if __name__=='__main__': unittest.main()\n",
                encoding="utf-8",
            )
            sb.write_bootstrap_config("kimi")
            cp = CoderProc(
                sb,
                startup_timeout=20.0,
            )
            try:
                cp.connect_provider("kimi", "kimi-k2-turbo-preview")
                cp.send("/approve auto")
                cp.wait_for("审批策略已设为", timeout=5.0)
                cp.send(
                    "请先了解项目结构和代码，然后在 calc/ops.py 中增加 sub(a,b) 函数，"
                    "并在 tests/test_ops.py 中补充 sub 的测试用例。"
                    "用 run_bash 跑 python3 -m unittest discover -s tests -v 确认通过。"
                    "完成回复 done。"
                )
                ok = cp.wait_for("[final]", timeout=180.0)
                stdout = cp.stdout()
                if not ok:
                    self.fail(f"no [final] within 180s.\nSTDOUT:\n{stdout}")
                # 验证 sub 函数被添加
                ops = (sb.cwd / "calc" / "ops.py").read_text(encoding="utf-8")
                self.assertIn("def sub", ops,
                              f"sub function not added; ops.py:\n{ops}")
                # 验证工具组合使用
                self.assertIn("edit_file  {", stdout)
                # 真实运行测试
                r = subprocess.run(
                    ["python3", "-m", "unittest", "discover", "-s", "tests", "-v"],
                    cwd=str(sb.cwd), capture_output=True, timeout=30,
                )
                self.assertEqual(
                    r.returncode, 0,
                    f"tests failed after incremental dev.\n"
                    f"stderr:{r.stderr!r}\nops.py:\n{ops}"
                )
            finally:
                cp.close()
        finally:
            sb.cleanup()

    def test_multi_bug_fix_with_grep(self):
        """多文件多 bug 修复：种入 3 处 bug，模型需用 run_bash 复现→
        grep_search / read_file 定位→edit_file 修复→run_bash 验证。
        触发 grep_search + read_file + edit_file + run_bash 组合。"""
        import subprocess
        sb = Sandbox.create()
        try:
            # 种入项目，含 3 处 bug
            (sb.cwd / "myapp").mkdir()
            (sb.cwd / "tests").mkdir()
            (sb.cwd / "myapp" / "__init__.py").write_text("", encoding="utf-8")
            (sb.cwd / "myapp" / "calc.py").write_text(
                "def add(a, b): return a + b\n"
                "def divide(a, b):\n"
                "    if b == 0: return 0\n"
                "    return a / b\n"
                "def factorial(n):\n"
                "    if n < 0: raise ValueError('negative')\n"
                "    if n == 0: return 1\n"
                "    r = 1\n"
                "    for i in range(1, n): r *= i\n"
                "    return r\n",
                encoding="utf-8",
            )
            (sb.cwd / "tests" / "__init__.py").write_text("", encoding="utf-8")
            (sb.cwd / "tests" / "test_calc.py").write_text(
                "import unittest\n"
                "from myapp.calc import add, divide, factorial\n\n"
                "class T(unittest.TestCase):\n"
                "    def test_add(self): self.assertEqual(add(2,3), 5)\n"
                "    def test_div(self): self.assertEqual(divide(10,2), 5.0)\n"
                "    def test_div_zero(self):\n"
                "        with self.assertRaises(ValueError): divide(1, 0)\n"
                "    def test_fact5(self): self.assertEqual(factorial(5), 120)\n"
                "    def test_fact0(self): self.assertEqual(factorial(0), 1)\n\n"
                "if __name__=='__main__': unittest.main()\n",
                encoding="utf-8",
            )
            sb.write_bootstrap_config("kimi")
            cp = CoderProc(
                sb,
                startup_timeout=20.0,
            )
            try:
                cp.connect_provider("kimi", "kimi-k2-turbo-preview")
                cp.send("/approve auto")
                cp.wait_for("审批策略已设为", timeout=5.0)
                cp.send(
                    "运行 python3 -m unittest discover -s tests 有测试失败。"
                    "请用 run_bash 复现，用 read_file 和 grep_search 定位 bug，"
                    "用 edit_file 修复（不要改测试），最后确认全部通过。"
                    "完成回复 done。"
                )
                ok = cp.wait_for("[final]", timeout=180.0)
                stdout = cp.stdout()
                if not ok:
                    self.fail(f"no [final] within 180s.\nSTDOUT:\n{stdout}")
                # 验证 bug 已修复
                src = (sb.cwd / "myapp" / "calc.py").read_text(encoding="utf-8")
                # factorial 的 range 应该包含 n
                self.assertIn("n + 1", src.replace("n+1", "n + 1"),
                              f"factorial bug not fixed; calc.py:\n{src}")
                # divide 应该抛 ValueError
                self.assertIn("ValueError", src,
                              f"divide bug not fixed; calc.py:\n{src}")
                # 测试文件不应被修改
                test_src = (sb.cwd / "tests" / "test_calc.py").read_text(encoding="utf-8")
                self.assertIn("factorial(5), 120", test_src)
                # 真实运行验证
                r = subprocess.run(
                    ["python3", "-m", "unittest", "discover", "-s", "tests"],
                    cwd=str(sb.cwd), capture_output=True, timeout=30,
                )
                self.assertEqual(
                    r.returncode, 0,
                    f"tests still failing.\nstderr:{r.stderr!r}\ncalc.py:\n{src}"
                )
                # 至少使用了 run_bash + edit_file
                self.assertIn("run_bash  {", stdout)
                self.assertIn("edit_file  {", stdout)
            finally:
                cp.close()
        finally:
            sb.cleanup()

    def test_thinking_model_bug_fix(self):
        """使用 kimi-k2.6 思考模型做 bug 修复：验证 reasoning_content
        在 assistant 消息中正确保留并回传（否则 API 会返回 HTTP 400）。
        触发 run_bash + read_file + edit_file 组合工具链。"""
        import subprocess
        sb = Sandbox.create()
        try:
            (sb.cwd / "webapp").mkdir()
            (sb.cwd / "tests").mkdir()
            (sb.cwd / "webapp" / "__init__.py").write_text("", encoding="utf-8")
            (sb.cwd / "webapp" / "models.py").write_text(
                "class User:\n"
                "    def __init__(self, name, age):\n"
                "        self.name = name\n"
                "        self.age = age\n\n"
                "    def is_adult(self):\n"
                "        return self.age > 18  # BUG: should be >= 18\n\n"
                "    def display_name(self):\n"
                "        return self.name.lower()  # BUG: should be title()\n",
                encoding="utf-8",
            )
            (sb.cwd / "tests" / "__init__.py").write_text("", encoding="utf-8")
            (sb.cwd / "tests" / "test_models.py").write_text(
                "import unittest\n"
                "from webapp.models import User\n\n"
                "class TestUser(unittest.TestCase):\n"
                "    def test_is_adult_18(self):\n"
                "        u = User('test', 18)\n"
                "        self.assertTrue(u.is_adult())\n\n"
                "    def test_display_name(self):\n"
                "        u = User('john doe', 25)\n"
                "        self.assertEqual(u.display_name(), 'John Doe')\n\n"
                "if __name__=='__main__': unittest.main()\n",
                encoding="utf-8",
            )
            sb.write_bootstrap_config("kimi")
            cp = CoderProc(
                sb,
                startup_timeout=20.0,
            )
            try:
                cp.connect_provider("kimi", "kimi-k2.6")
                cp.send("/approve auto")
                cp.wait_for("审批策略已设为", timeout=5.0)
                cp.send(
                    "运行 python3 -m unittest discover -s tests -v 有测试失败。"
                    "请用 run_bash 复现，用 read_file 查看源码找到 bug，"
                    "用 edit_file 修复（不要修改测试），最终让所有测试通过。"
                    "完成后回复 done。"
                )
                ok = cp.wait_for("[final]", timeout=240.0)
                stdout = cp.stdout()
                if not ok:
                    self.fail(f"no [final] within 240s.\nSTDOUT:\n{stdout[-2000:]}")
                # 验证 bug 已修复
                src = (sb.cwd / "webapp" / "models.py").read_text(encoding="utf-8")
                # 测试文件不应被修改
                test_src = (sb.cwd / "tests" / "test_models.py").read_text(encoding="utf-8")
                self.assertIn("is_adult", test_src)
                # 真实运行验证
                r = subprocess.run(
                    ["python3", "-m", "unittest", "discover", "-s", "tests"],
                    cwd=str(sb.cwd), capture_output=True, timeout=30,
                )
                self.assertEqual(
                    r.returncode, 0,
                    f"tests still failing.\nstderr:{r.stderr!r}\nmodels.py:\n{src}"
                )
                self.assertIn("run_bash  {", stdout)
                self.assertIn("edit_file  {", stdout)
            finally:
                cp.close()
        finally:
            sb.cleanup()

    def test_incremental_dev_with_k2_5(self):
        """使用 kimi-k2.5 做增量开发：在已有项目上添加新函数 + 测试。
        触发 list_dir → read_file → edit_file/write_file → run_bash 链路。"""
        import subprocess
        sb = Sandbox.create()
        try:
            (sb.cwd / "mathlib").mkdir()
            (sb.cwd / "tests").mkdir()
            (sb.cwd / "mathlib" / "__init__.py").write_text("", encoding="utf-8")
            (sb.cwd / "mathlib" / "basic.py").write_text(
                "def add(a, b):\n    return a + b\n\n"
                "def sub(a, b):\n    return a - b\n\n"
                "def mul(a, b):\n    return a * b\n",
                encoding="utf-8",
            )
            (sb.cwd / "tests" / "__init__.py").write_text("", encoding="utf-8")
            (sb.cwd / "tests" / "test_basic.py").write_text(
                "import unittest\n"
                "from mathlib.basic import add, sub, mul\n\n"
                "class TestBasic(unittest.TestCase):\n"
                "    def test_add(self): self.assertEqual(add(2,3), 5)\n"
                "    def test_sub(self): self.assertEqual(sub(5,3), 2)\n"
                "    def test_mul(self): self.assertEqual(mul(4,3), 12)\n\n"
                "if __name__=='__main__': unittest.main()\n",
                encoding="utf-8",
            )
            sb.write_bootstrap_config("kimi")
            cp = CoderProc(
                sb,
                startup_timeout=20.0,
            )
            try:
                cp.connect_provider("kimi", "kimi-k2.5")
                cp.send("/approve auto")
                cp.wait_for("审批策略已设为", timeout=5.0)
                cp.send(
                    "请先了解项目结构和代码，然后在 mathlib/basic.py 中增加 "
                    "div(a,b) 除法函数（b==0 抛 ValueError），"
                    "并在 tests/test_basic.py 中补充 div 的测试用例。"
                    "用 run_bash 跑 python3 -m unittest discover -s tests -v 确认通过。"
                    "完成回复 done。"
                )
                ok = cp.wait_for("[final]", timeout=240.0)
                stdout = cp.stdout()
                if not ok:
                    self.fail(f"no [final] within 240s.\nSTDOUT:\n{stdout[-2000:]}")
                # 验证 div 函数被添加
                ops = (sb.cwd / "mathlib" / "basic.py").read_text(encoding="utf-8")
                self.assertIn("def div", ops,
                              f"div function not added; basic.py:\n{ops}")
                # 真实运行测试
                r = subprocess.run(
                    ["python3", "-m", "unittest", "discover", "-s", "tests", "-v"],
                    cwd=str(sb.cwd), capture_output=True, timeout=30,
                )
                self.assertEqual(
                    r.returncode, 0,
                    f"tests failed.\nstderr:{r.stderr!r}\nbasic.py:\n{ops}"
                )
            finally:
                cp.close()
        finally:
            sb.cleanup()


if __name__ == "__main__":
    unittest.main()
