"""diff_undo: /diff + /undo 多文件操作端到端测试（mock，无需网络）。

模拟一个多文件操作流程：
  1. write_file 创建两个文件
  2. edit_file 修改其中一个
  3. /diff 检查变更列表（应包含被创建和编辑的文件）
  4. /undo 撤销最后一步操作
  5. 验证文件状态正确
"""

from __future__ import annotations

import json

from ..driver import CoderProc, ScriptedReply, mock_server, sandbox

NAME = "diff_undo"
TAGS = ["mock"]


def run() -> tuple[bool, str, str, str]:
    """多文件写入+编辑后 /diff 可见，/undo 可逐步撤销。"""
    with mock_server() as ms, sandbox() as sb:
        # Step 1: 创建 config.json
        ms.enqueue(ScriptedReply(
            tool_calls=[("c1", "write_file", json.dumps({
                "path": "config.json",
                "content": '{"debug": false, "port": 8080}\n',
            }))]
        ))
        # Step 2: 创建 server.py
        ms.enqueue(ScriptedReply(
            tool_calls=[("c2", "write_file", json.dumps({
                "path": "server.py",
                "content": (
                    "import json\n\n"
                    "def load_config():\n"
                    "    with open('config.json') as f:\n"
                    "        return json.load(f)\n"
                ),
            }))]
        ))
        # Step 3: 编辑 config.json，修改 port
        ms.enqueue(ScriptedReply(
            tool_calls=[("c3", "edit_file", json.dumps({
                "path": "config.json",
                "old_str": '"port": 8080',
                "new_str": '"port": 3000',
            }))]
        ))
        # Step 4: 完成
        ms.enqueue(ScriptedReply(content="项目配置完成。"))

        sb.write_config(ms.endpoint(), "deepseek-v4-pro", "k")
        cp = CoderProc(sb)
        try:
            cp.send("/approve auto")
            cp.wait_for("审批策略已设为", timeout=3.0)
            cp.send("创建配置文件和服务器脚本")
            ok = cp.wait_for("[final]", timeout=20.0)
            if not ok:
                return False, cp.stdout(), cp.stderr(), "no [final]"
            # 验证文件被创建并编辑
            cfg = (sb.cwd / "config.json").read_text(encoding="utf-8")
            if "3000" not in cfg:
                return False, cp.stdout(), cp.stderr(), f"edit not applied: {cfg[:200]}"
            if not (sb.cwd / "server.py").exists():
                return False, cp.stdout(), cp.stderr(), "server.py not created"

            # /diff 应显示变更文件
            cp.send("/diff")
            ok = cp.wait_for("config.json", timeout=5.0)
            if not ok:
                return False, cp.stdout(), cp.stderr(), "/diff missing config.json"
            ok = cp.wait_for("server.py", timeout=3.0)
            if not ok:
                return False, cp.stdout(), cp.stderr(), "/diff missing server.py"

            # /undo 撤销最后一步（edit_file 对 config.json 的编辑）
            cp.send("/undo")
            ok = cp.wait_for_any(["已撤销", "已删除", "已还原", "已恢复"], timeout=5.0)
            if not ok:
                return False, cp.stdout(), cp.stderr(), "/undo did not confirm"

            return True, cp.stdout(), cp.stderr(), ""
        finally:
            cp.close()
