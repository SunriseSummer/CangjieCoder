"""compact: /compact 多轮多工具历史压缩测试（mock，无需网络）。

模拟三轮对话，每轮使用不同工具类型：
  1. write_file 创建文件
  2. read_file + edit_file 读取并修改
  3. list_dir + run_bash 查看目录和运行命令
然后 /compact 1 压缩历史，验证压缩成功。
"""

from __future__ import annotations

import json

from ..driver import CoderProc, ScriptedReply, mock_server, sandbox

NAME = "compact"
TAGS = ["mock"]


def run() -> tuple[bool, str, str, str]:
    """三轮多工具对话后 /compact 1 压缩历史。"""
    with mock_server() as ms, sandbox() as sb:
        # 第一轮：write_file 创建文件
        ms.enqueue(ScriptedReply(
            tool_calls=[("c1", "write_file", json.dumps({
                "path": "notes.md",
                "content": "# Notes\n\n- item 1\n",
            }))]
        ))
        ms.enqueue(ScriptedReply(content="已创建 notes.md。"))

        # 第二轮：read_file + edit_file
        ms.enqueue(ScriptedReply(
            tool_calls=[("c2", "read_file", json.dumps({
                "path": "notes.md",
            }))]
        ))
        ms.enqueue(ScriptedReply(
            tool_calls=[("c3", "edit_file", json.dumps({
                "path": "notes.md",
                "old_str": "- item 1",
                "new_str": "- item 1\n- item 2\n- item 3",
            }))]
        ))
        ms.enqueue(ScriptedReply(content="已添加两条记录。"))

        # 第三轮：list_dir 查看
        ms.enqueue(ScriptedReply(
            tool_calls=[("c4", "list_dir", json.dumps({"path": "."}))]
        ))
        ms.enqueue(ScriptedReply(content="项目目录确认完毕。"))

        sb.write_config(ms.endpoint(), "deepseek-v4-pro", "k")
        cp = CoderProc(sb)
        try:
            cp.send("/approve auto")
            cp.wait_for("审批策略已设为", timeout=3.0)

            # 第一轮
            cp.send("创建一个笔记文件")
            ok = cp.wait_for("[final]", timeout=15.0)
            if not ok:
                return False, cp.stdout(), cp.stderr(), "第一轮未完成"

            # 第二轮
            pos = cp.stdout_pos()
            cp.send("往笔记中追加两条记录")
            ok = cp.wait_for("[final]", timeout=15.0, after=pos)
            if not ok:
                return False, cp.stdout(), cp.stderr(), "第二轮未完成"

            # 第三轮
            pos = cp.stdout_pos()
            cp.send("看一下当前目录")
            ok = cp.wait_for("[final]", timeout=15.0, after=pos)
            if not ok:
                return False, cp.stdout(), cp.stderr(), "第三轮未完成"

            # 压缩历史
            cp.send("/compact 1")
            ok = cp.wait_for("历史已压缩", timeout=5.0)
            if not ok:
                return False, cp.stdout(), cp.stderr(), "compact 未触发"

            # 验证文件内容（确保工具链正常执行）
            content = (sb.cwd / "notes.md").read_text(encoding="utf-8")
            if "item 2" not in content:
                return False, cp.stdout(), cp.stderr(), f"edit not applied: {content[:200]}"

            return True, cp.stdout(), cp.stderr(), ""
        finally:
            cp.close()
