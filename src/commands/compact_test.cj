package cangjiecoder.commands

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import cangjiecoder.httpx.*

/**
 * /compact 命令的纯函数单元测试
 *
 * 我们测试两个核心助手：
 *  - `alignToBlockBoundary`：边界对齐确保 (assistant tool_calls) 与
 *    后续 role=tool 响应不被拆开 —— 这是 OpenAI 协议硬约束，
 *  - `renderCompactSummary`：摘要文本格式稳定，便于人和模型阅读
 */

@Test
class CompactTests {
    @TestCase
    func alignNonToolUnchanged() {
        let history = ArrayList<ChatMessage>()
        history.add(ChatMessage.user("u1"))
        history.add(ChatMessage.assistant("a1"))
        // idx=1 是 assistant，本身不是 tool，应原样返回
        @Expect(alignToBlockBoundary(history, 1), 1)
    }

    @TestCase
    func alignToolRollsBackToAssistant() {
        let history = ArrayList<ChatMessage>()
        history.add(ChatMessage.user("u1"))
        let tc: Array<ToolCall> = [ToolCall("c1", "read_file", "{}")]
        history.add(ChatMessage.assistantWithTools("", tc))
        history.add(ChatMessage.tool("c1", "result-1"))
        history.add(ChatMessage.user("u2"))
        // idx=2 是 tool，必须回退到对应 assistant=1
        @Expect(alignToBlockBoundary(history, 2), 1)
        // idx=3 是 user，不变
        @Expect(alignToBlockBoundary(history, 3), 3)
    }

    @TestCase
    func alignSkipsMultipleToolMessages() {
        let history = ArrayList<ChatMessage>()
        let tcs: Array<ToolCall> = [
            ToolCall("c1", "t1", "{}"),
            ToolCall("c2", "t2", "{}")
        ]
        history.add(ChatMessage.assistantWithTools("", tcs))
        history.add(ChatMessage.tool("c1", "r1"))
        history.add(ChatMessage.tool("c2", "r2"))
        // 两条 tool 响应均回退至 idx=0
        @Expect(alignToBlockBoundary(history, 1), 0)
        @Expect(alignToBlockBoundary(history, 2), 0)
    }

    @TestCase
    func renderSummaryShapeIsStable() {
        let names = HashMap<String, Int64>()
        names["edit_file"] = 3
        names["grep_search"] = 2
        let summary = renderCompactSummary(4, 5, 1, names)
        @Expect(summary.contains("[历史已压缩]"), true)
        @Expect(summary.contains("1 条 user"), true)
        @Expect(summary.contains("4 条 assistant"), true)
        @Expect(summary.contains("5 条 tool"), true)
        @Expect(summary.contains("edit_file×3"), true)
        @Expect(summary.contains("grep_search×2"), true)
    }

    @TestCase
    func renderSummaryOmitsToolsListWhenEmpty() {
        let summary = renderCompactSummary(2, 0, 1, HashMap<String, Int64>())
        @Expect(summary.contains("调用过的工具"), false)
        @Expect(summary.contains("2 条 assistant"), true)
    }

    @TestCase
    func renderSummaryToolNamesAreSorted() {
        // 修复前：HashMap 迭代顺序不确定，输出不可复现
        // 修复后：工具名按字典序排序
        let names = HashMap<String, Int64>()
        names["grep_search"] = 1
        names["edit_file"] = 2
        names["read_file"] = 3
        let summary = renderCompactSummary(1, 3, 1, names)
        let editIdx = summary.indexOf("edit_file").getOrThrow()
        let grepIdx = summary.indexOf("grep_search").getOrThrow()
        let readIdx = summary.indexOf("read_file").getOrThrow()
        // 字典序：edit_file < grep_search < read_file
        @Expect(editIdx < grepIdx, true)
        @Expect(grepIdx < readIdx, true)
    }
}
