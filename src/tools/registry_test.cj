package cangjiecoder.tools

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ToolRegistryTests {
    @TestCase
    func emptyRegistry() {
        let r = ToolRegistry()
        @Expect(r.names().size, 0)
        @Expect(r.all().size, 0)
        @Expect(r.get("anything").isNone(), true)
    }

    @TestCase
    func addPreservesInsertionOrder() {
        let store = TodoStore()
        let r = ToolRegistry()
        r.add(ReadFileTool())
        r.add(WriteFileTool())
        r.add(TodoReadTool(store))
        let ns = r.names()
        @Expect(ns[0], "read_file")
        @Expect(ns[1], "write_file")
        @Expect(ns[2], "todo_read")
    }

    @TestCase
    func addReplacesByName() {
        let r = ToolRegistry()
        r.add(ReadFileTool())
        r.add(ReadFileTool())  // 重复添加同名工具
        @Expect(r.names().size, 1)
    }

    @TestCase
    func removeDeletesAndPreservesOrder() {
        let store = TodoStore()
        let r = ToolRegistry()
        r.add(ReadFileTool())
        r.add(WriteFileTool())
        r.add(TodoReadTool(store))
        r.remove("write_file")
        let ns = r.names()
        @Expect(ns.size, 2)
        @Expect(ns[0], "read_file")
        @Expect(ns[1], "todo_read")
        @Expect(r.get("write_file").isNone(), true)
    }

    @TestCase
    func removeUnknownIsNoOp() {
        let r = ToolRegistry()
        r.add(ReadFileTool())
        r.remove("nope")
        @Expect(r.names().size, 1)
    }

    @TestCase
    func defaultRegistryHasNineTools() {
        let store = TodoStore()
        let r = defaultRegistry(store)
        @Expect(r.names().size, 9)
        // 必须包含的核心工具
        let mustHave = ["read_file", "write_file", "edit_file", "list_dir",
                        "glob_search", "grep_search", "run_bash",
                        "todo_write", "todo_read"]
        for (name in mustHave) {
            @Expect(r.get(name).isSome(), true)
        }
    }

    @TestCase
    func defaultRegistryApprovalLevels() {
        let store = TodoStore()
        let r = defaultRegistry(store)
        let sensitive = ["write_file", "edit_file", "run_bash"]
        for (name in sensitive) {
            let t = r.get(name).getOrThrow()
            let isSensitive = match (t.approval) {
                case Sensitive => true
                case Safe => false
            }
            @Expect(isSensitive, true)
        }
        let safe = ["read_file", "list_dir", "glob_search", "grep_search",
                    "todo_read", "todo_write"]
        for (name in safe) {
            let t = r.get(name).getOrThrow()
            let isSafe = match (t.approval) {
                case Safe => true
                case Sensitive => false
            }
            @Expect(isSafe, true)
        }
    }
}
