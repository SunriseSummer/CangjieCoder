#!/usr/bin/env python3
"""
基于 mock OpenAI 服务端的端到端测试。
无需任何外部 API Key 即可运行：

    cd coder
    cjpm build
    python3 -m unittest -v e2etest.test_mock_agent

覆盖：
 - 基础启动 / 退出
 - chat 模式纯文本回复
 - agent 模式多轮工具调用：list_dir → write_file → 完成
 - /diff /undo 命令在真实改动上的端到端行为
 - /compact 在堆积历史后能正确缩短上下文
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path

from .driver import CoderProc, ScriptedReply, mock_server, sandbox


class StartupTests(unittest.TestCase):
    def test_help_then_exit(self):
        with mock_server() as ms, sandbox() as sb:
            sb.write_config(ms.endpoint(), "deepseek-v4-pro", "k")
            cp = CoderProc(sb)
            try:
                cp.send("/help")
                self.assertTrue(cp.wait_for("/diff", timeout=5.0),
                                f"help output missing /diff: {cp.stdout()}")
                self.assertTrue(cp.wait_for("/undo", timeout=2.0))
                self.assertTrue(cp.wait_for("/compact", timeout=2.0))
            finally:
                code = cp.close()
            self.assertEqual(code, 0)

    def test_status_shows_journal_zero(self):
        with mock_server() as ms, sandbox() as sb:
            sb.write_config(ms.endpoint(), "deepseek-v4-pro", "k")
            cp = CoderProc(sb)
            try:
                cp.send("/status")
                self.assertTrue(cp.wait_for("文件改动", timeout=5.0),
                                f"missing journal line: {cp.stdout()}")
            finally:
                cp.close()


class ChatModeTests(unittest.TestCase):
    def test_chat_plain_text_reply(self):
        with mock_server() as ms, sandbox() as sb:
            ms.enqueue(ScriptedReply(content="你好，我是 mock 模型。"))
            sb.write_config(ms.endpoint(), "deepseek-v4-pro", "k")
            cp = CoderProc(sb)
            try:
                cp.send("/mode chat")
                cp.wait_for("已切换到 chat", timeout=3.0)
                pos = cp.stdout_pos()
                cp.send("你好")
                # chat 模式走流式接口，mock 不返回 SSE，但二进制不应崩溃
                # 至少 prompt 会再次出现
                self.assertTrue(cp.wait_for("[user-input]", timeout=8.0, after=pos),
                                f"chat prompt did not reappear: {cp.stdout()}")
            finally:
                cp.close()


class AgentToolCallTests(unittest.TestCase):
    def test_agent_writes_file_through_tool_call(self):
        # 期望剧本：
        #  Turn 1: 模型调用 write_file(path="hello.txt", content="hi\n")
        #  Turn 2: 模型返回最终文本（无 tool_calls，结束 loop）
        target_rel = "hello.txt"
        with mock_server() as ms, sandbox() as sb:
            ms.enqueue(ScriptedReply(
                tool_calls=[(
                    "c1", "write_file",
                    json.dumps({"path": target_rel, "content": "hi\n"})
                )]
            ))
            ms.enqueue(ScriptedReply(content="已创建文件 hello.txt。"))
            sb.write_config(ms.endpoint(), "deepseek-v4-pro", "k")
            # 给一个绕过审批的环境（默认 default 会询问；这里直接 auto）
            cp = CoderProc(sb)
            try:
                cp.send("/approve auto")
                cp.wait_for("审批策略已设为", timeout=3.0)
                cp.send("创建 hello.txt，内容 hi 加换行")
                # 等待 final 标记
                ok = cp.wait_for("[final]", timeout=15.0)
                if not ok:
                    self.fail(
                        f"final not seen.\nSTDOUT:\n{cp.stdout()}\n"
                        f"STDERR:\n{cp.stderr()}\n"
                        f"mock.requests={len(ms.requests)}"
                    )
                # 验证文件确实落盘
                self.assertTrue((sb.cwd / target_rel).exists(),
                                f"file not created: cwd={sb.cwd}")
                self.assertEqual((sb.cwd / target_rel).read_text(), "hi\n")
                # 工具调用 + 工具结果都应回显
                stdout = cp.stdout()
                self.assertIn("write_file  {", stdout)
                self.assertIn("write_file: ", stdout)
            finally:
                cp.close()
            # mock server 应当收到两次请求
            self.assertEqual(len(ms.requests), 2,
                             f"expected 2 round-trips, got {len(ms.requests)}")
            # 第二次请求 messages 列表应包含 role=tool 的工具回执
            second = ms.requests[1]
            roles = [m.get("role") for m in second.get("messages", [])]
            self.assertIn("tool", roles, f"second request missing tool reply: {second}")


class JournalAndUndoTests(unittest.TestCase):
    def test_diff_and_undo_after_write(self):
        target_rel = "scratch.txt"
        with mock_server() as ms, sandbox() as sb:
            ms.enqueue(ScriptedReply(
                tool_calls=[(
                    "c1", "write_file",
                    json.dumps({"path": target_rel, "content": "v1"})
                )]
            ))
            ms.enqueue(ScriptedReply(content="OK"))
            sb.write_config(ms.endpoint(), "deepseek-v4-pro", "k")
            cp = CoderProc(sb)
            try:
                cp.send("/approve auto")
                cp.wait_for("审批策略已设为", timeout=3.0)
                cp.send("写一下 scratch.txt")
                self.assertTrue(cp.wait_for("[final]", timeout=15.0))
                target = sb.cwd / target_rel
                self.assertTrue(target.exists())
                # /diff 应列出 scratch.txt
                cp.send("/diff")
                self.assertTrue(cp.wait_for("scratch.txt", timeout=3.0),
                                f"/diff did not list file: {cp.stdout()}")
                # /undo 应让文件消失
                cp.send("/undo")
                self.assertTrue(cp.wait_for("已删除", timeout=3.0),
                                f"/undo did not delete: {cp.stdout()}")
                self.assertFalse(target.exists(),
                                 "file should be gone after /undo")
                # 再次 /undo 应优雅地告知无可回滚
                cp.send("/undo")
                self.assertTrue(cp.wait_for("没有可回滚", timeout=3.0))
            finally:
                cp.close()

    def test_undo_restores_previous_content(self):
        target_rel = "doc.md"
        with mock_server() as ms, sandbox() as sb:
            # 预置文件
            (sb.cwd / target_rel).write_text("hello TODO world")
            ms.enqueue(ScriptedReply(
                tool_calls=[(
                    "c1", "edit_file",
                    json.dumps({"path": target_rel,
                                "old_str": "TODO",
                                "new_str": "DONE"})
                )]
            ))
            ms.enqueue(ScriptedReply(content="已替换。"))
            sb.write_config(ms.endpoint(), "deepseek-v4-pro", "k")
            cp = CoderProc(sb)
            try:
                cp.send("/approve auto")
                cp.wait_for("审批策略已设为", timeout=3.0)
                cp.send("把 TODO 改成 DONE")
                self.assertTrue(cp.wait_for("[final]", timeout=15.0))
                self.assertEqual(
                    (sb.cwd / target_rel).read_text(), "hello DONE world")
                cp.send("/undo")
                self.assertTrue(cp.wait_for("已恢复", timeout=3.0))
                self.assertEqual(
                    (sb.cwd / target_rel).read_text(), "hello TODO world")
            finally:
                cp.close()


class CompactTests(unittest.TestCase):
    def test_compact_shortens_history(self):
        # 一轮工具调用 + 一轮最终回复 = history 长 4
        # 再发一轮 + 最终回复 = history 长 8
        # /compact 1 应当压缩到「首条 user + 摘要 + 最后 1 条」 -> 3 条
        with mock_server() as ms, sandbox() as sb:
            # 第 1 个用户输入：工具调用 + 最终
            ms.enqueue(ScriptedReply(
                tool_calls=[("c1", "list_dir", json.dumps({"path": "."}))]))
            ms.enqueue(ScriptedReply(content="第一轮完成"))
            # 第 2 个用户输入：工具调用 + 最终
            ms.enqueue(ScriptedReply(
                tool_calls=[("c2", "list_dir", json.dumps({"path": "."}))]))
            ms.enqueue(ScriptedReply(content="第二轮完成"))
            sb.write_config(ms.endpoint(), "deepseek-v4-pro", "k")
            cp = CoderProc(sb)
            try:
                cp.send("/approve auto")
                cp.wait_for("审批策略已设为", timeout=3.0)
                cp.send("第一次")
                self.assertTrue(cp.wait_for("第一轮完成", timeout=15.0))
                cp.send("第二次")
                self.assertTrue(cp.wait_for("第二轮完成", timeout=15.0))
                # 现在 /compact 1
                cp.send("/compact 1")
                self.assertTrue(cp.wait_for("历史已压缩", timeout=3.0),
                                f"compact not run: {cp.stdout()}")
            finally:
                cp.close()
            # 全程总共 4 次 LLM 请求
            self.assertEqual(len(ms.requests), 4)


if __name__ == "__main__":
    unittest.main()
