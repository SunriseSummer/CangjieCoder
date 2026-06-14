"""agent_write: 多步工具调用链测试（mock，无需网络）。

模拟 LLM 执行一个完整的文件操作流程：
  1. write_file 创建主文件
  2. write_file 创建第二个文件
  3. read_file 读取确认
  4. edit_file 修改文件
  5. 最终确认

覆盖 write_file → read_file → edit_file 全链路。
"""

from __future__ import annotations

import json

from ..driver import CoderProc, ScriptedReply, mock_server, sandbox

NAME = "agent_write"
TAGS = ["mock"]


def run() -> tuple[bool, str, str, str]:
    """模拟 LLM 多步工具调用链，验证文件创建→读取→编辑流程。"""
    with mock_server() as ms, sandbox() as sb:
        # Step 1: 创建 app.py
        ms.enqueue(ScriptedReply(
            tool_calls=[("c1", "write_file", json.dumps({
                "path": "app.py",
                "content": (
                    "def greet(name):\n"
                    "    return 'Hello, ' + name\n\n"
                    "if __name__ == '__main__':\n"
                    "    print(greet('World'))\n"
                ),
            }))]
        ))
        # Step 2: 创建 utils.py
        ms.enqueue(ScriptedReply(
            tool_calls=[("c2", "write_file", json.dumps({
                "path": "utils.py",
                "content": (
                    "def add(a, b):\n"
                    "    return a + b\n\n"
                    "def multiply(a, b):\n"
                    "    return a * b\n"
                ),
            }))]
        ))
        # Step 3: 读取 app.py 确认内容
        ms.enqueue(ScriptedReply(
            tool_calls=[("c3", "read_file", json.dumps({
                "path": "app.py",
            }))]
        ))
        # Step 4: 编辑 app.py，添加 import
        ms.enqueue(ScriptedReply(
            tool_calls=[("c4", "edit_file", json.dumps({
                "path": "app.py",
                "old_str": "def greet(name):",
                "new_str": "from utils import add\n\ndef greet(name):",
            }))]
        ))
        # Step 5: 完成
        ms.enqueue(ScriptedReply(content="项目创建完成：app.py 和 utils.py 已就绪，已添加 import 引用。"))

        sb.write_config(ms.endpoint(), "deepseek-v4-pro", "k")
        cp = CoderProc(sb)
        try:
            cp.send("/approve auto")
            cp.wait_for("审批策略已设为", timeout=3.0)
            cp.send("创建一个包含 app.py 和 utils.py 的 Python 项目")
            ok = cp.wait_for("[final]", timeout=30.0)
            stdout, stderr = cp.stdout(), cp.stderr()
            if not ok:
                return False, stdout, stderr, "no [final] within 30s"
            # 验证两个文件都被创建
            if not (sb.cwd / "app.py").exists():
                return False, stdout, stderr, "app.py not created"
            if not (sb.cwd / "utils.py").exists():
                return False, stdout, stderr, "utils.py not created"
            # 验证 edit_file 生效（app.py 包含 import）
            app_content = (sb.cwd / "app.py").read_text(encoding="utf-8")
            if "from utils import add" not in app_content:
                return False, stdout, stderr, f"edit_file not applied: {app_content[:200]}"
            # 验证关键工具调用都出现
            if "write_file  {" not in stdout:
                return False, stdout, stderr, "no write_file tool call"
            if "read_file  {" not in stdout:
                return False, stdout, stderr, "no read_file tool call"
            if "edit_file  {" not in stdout:
                return False, stdout, stderr, "no edit_file tool call"
            return True, stdout, stderr, ""
        finally:
            cp.close()
