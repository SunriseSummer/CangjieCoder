package cangjiecoder.tools

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class TodoStoreTests {
    @TestCase
    func newStoreIsEmpty() {
        let store = TodoStore()
        @Expect(store.items.size, 0)
        @Expect(store.render(), "<尚无 TODO 项>")
    }

    @TestCase
    func replaceAllSetsItems() {
        let store = TodoStore()
        let items = ArrayList<TodoItem>()
        items.add(TodoItem("step a", "in_progress", "doing a"))
        items.add(TodoItem("step b", "pending", "doing b"))
        store.replaceAll(items)
        @Expect(store.items.size, 2)
        @Expect(store.items[0].content, "step a")
        @Expect(store.items[1].status, "pending")
    }

    @TestCase
    func renderMarksStatuses() {
        let store = TodoStore()
        let items = ArrayList<TodoItem>()
        items.add(TodoItem("a", "completed", "_"))
        items.add(TodoItem("b", "in_progress", "_"))
        items.add(TodoItem("c", "pending", "_"))
        store.replaceAll(items)
        let rendered = store.render()
        @Expect(rendered.contains("[x] a"), true)
        @Expect(rendered.contains("[~] b"), true)
        @Expect(rendered.contains("[ ] c"), true)
    }

    @TestCase
    func replaceAllOverwrites() {
        let store = TodoStore()
        let first = ArrayList<TodoItem>()
        first.add(TodoItem("a", "pending", "_"))
        store.replaceAll(first)
        let second = ArrayList<TodoItem>()
        second.add(TodoItem("b", "pending", "_"))
        second.add(TodoItem("c", "pending", "_"))
        store.replaceAll(second)
        @Expect(store.items.size, 2)
        @Expect(store.items[0].content, "b")
    }
}

@Test
class TodoToolsTests {
    @TestCase
    func todoWriteValidates() {
        let store = TodoStore()
        let tool = TodoWriteTool(store)
        // 缺少 todos 字段
        @Expect(tool.execute("{}").isError, true)
        // todos 不是数组
        @Expect(tool.execute(##"{"todos":"oops"}"##).isError, true)
    }

    @TestCase
    func todoWriteRejectsEmptyContent() {
        let tool = TodoWriteTool(TodoStore())
        let result = tool.execute(##"{"todos":[{"content":"","status":"pending","activeForm":"_"}]}"##)
        @Expect(result.isError, true)
    }

    @TestCase
    func todoWriteRejectsInvalidStatus() {
        // 修复前：无效的 status 值被直接接受
        // 修复后：仅允许 pending/in_progress/completed
        let tool = TodoWriteTool(TodoStore())
        let result = tool.execute(##"{"todos":[{"content":"task","status":"invalid","activeForm":"_"}]}"##)
        @Expect(result.isError, true)
        @Expect(result.content.contains("status 无效"), true)
    }

    @TestCase
    func todoWriteAcceptsAllValidStatuses() {
        let tool = TodoWriteTool(TodoStore())
        let result = tool.execute(##"{"todos":[
            {"content":"a","status":"pending","activeForm":"_"},
            {"content":"b","status":"in_progress","activeForm":"_"},
            {"content":"c","status":"completed","activeForm":"_"}
        ]}"##)
        @Expect(result.isError, false)
    }

    @TestCase
    func todoWriteEnforcesSingleInProgress() {
        let tool = TodoWriteTool(TodoStore())
        let json = ##"{"todos":[
            {"content":"a","status":"in_progress","activeForm":"_"},
            {"content":"b","status":"in_progress","activeForm":"_"}
        ]}"##
        let result = tool.execute(json)
        @Expect(result.isError, true)
        @Expect(result.content.contains("in_progress"), true)
    }

    @TestCase
    func todoWriteHappyPathAndRead() {
        let store = TodoStore()
        let write = TodoWriteTool(store)
        let read = TodoReadTool(store)
        let result = write.execute(##"{"todos":[
            {"content":"调研","status":"in_progress","activeForm":"调研中"},
            {"content":"实现","status":"pending","activeForm":"实现中"}
        ]}"##)
        @Expect(result.isError, false)
        @Expect(store.items.size, 2)
        let view = read.execute("{}")
        @Expect(view.isError, false)
        @Expect(view.content.contains("调研"), true)
        @Expect(view.content.contains("实现"), true)
    }

    @TestCase
    func todoToolApprovalLevels() {
        let store = TodoStore()
        let write = TodoWriteTool(store)
        let read = TodoReadTool(store)
        let writeSafe = match (write.approval) { case Safe => true; case _ => false }
        let readSafe = match (read.approval) { case Safe => true; case _ => false }
        @Expect(writeSafe, true)
        @Expect(readSafe, true)
    }
}
