package cangjiecoder.tools

import std.collection.*
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*

/**
 * FileJournal 单元测试覆盖：
 *  - record 对「不存在」与「已存在」文件分别记录正确状态
 *  - popLast 弹栈与 size 同步
 *  - revert 在两种历史路径上正确恢复磁盘
 *  - 集成：EditFileTool 与 WriteFileTool 在改动前自动 record
 *  - summary 去重并报告 before/now 字节数
 */
func tmpJournalDir(): Path {
    return newSandbox()
}

@Test
class FileJournalTests {
    @TestCase
    func recordForNonExistentFile() {
        let dir = tmpJournalDir()
        let j = FileJournal()
        let p = dir.join("new.txt").toString()
        j.record(p, "write_file")
        @Expect(j.size(), 1)
        let snap = j.entries()[0]
        @Expect(snap.existedBefore, false)
        @Expect(snap.contentBefore.size, 0)
        @Expect(snap.tool, "write_file")
        @Expect(snap.path, p)
    }

    @TestCase
    func recordForExistingFileCapturesBytes() {
        let dir = tmpJournalDir()
        let p = dir.join("hello.txt")
        File.writeTo(p, "hello world".toArray())
        let j = FileJournal()
        j.record(p.toString(), "edit_file")
        @Expect(j.size(), 1)
        let snap = j.entries()[0]
        @Expect(snap.existedBefore, true)
        @Expect(String.fromUtf8(snap.contentBefore), "hello world")
    }

    @TestCase
    func popLastDecreasesSize() {
        let j = FileJournal()
        j.record("/tmp/cj_a", "edit_file")
        j.record("/tmp/cj_b", "edit_file")
        @Expect(j.size(), 2)
        match (j.popLast()) {
            case Some(s) => @Expect(s.path, "/tmp/cj_b")
            case None => @Fail("expected Some")
        }
        @Expect(j.size(), 1)
        match (j.popLast()) {
            case Some(s) => @Expect(s.path, "/tmp/cj_a")
            case None => @Fail("expected Some")
        }
        @Expect(j.size(), 0)
        match (j.popLast()) {
            case Some(_) => @Fail("expected None")
            case None => ()
        }
    }

    @TestCase
    func revertRestoresExistingFile() {
        let dir = tmpJournalDir()
        let p = dir.join("a.txt")
        File.writeTo(p, "v1".toArray())
        let j = FileJournal()
        j.record(p.toString(), "edit_file")
        // 模拟工具改动
        File.writeTo(p, "v2-changed".toArray())
        @Expect(String.fromUtf8(File.readFrom(p)), "v2-changed")
        match (j.popLast()) {
            case Some(s) => j.revert(s)
            case None => @Fail("expected snapshot")
        }
        @Expect(String.fromUtf8(File.readFrom(p)), "v1")
    }

    @TestCase
    func revertDeletesFileThatDidNotExist() {
        let dir = tmpJournalDir()
        let p = dir.join("ghost.txt")
        @Expect(exists(p), false)
        let j = FileJournal()
        j.record(p.toString(), "write_file")
        // 模拟工具创建
        File.writeTo(p, "created".toArray())
        @Expect(exists(p), true)
        match (j.popLast()) {
            case Some(s) => j.revert(s)
            case None => @Fail("expected snapshot")
        }
        @Expect(exists(p), false)
    }

    @TestCase
    func editFileToolRecordsSnapshot() {
        let dir = tmpJournalDir()
        let p = dir.join("readme.md")
        File.writeTo(p, "# TODO: write docs".toArray())
        let j = FileJournal()
        let tool = EditFileTool(j)
        let args = jsonPath(p.toString(), "\"old_str\":\"TODO\",\"new_str\":\"待办\"")
        let r = tool.execute(args)
        @Expect(r.isError, false)
        @Expect(j.size(), 1)
        @Expect(j.entries()[0].existedBefore, true)
        @Expect(String.fromUtf8(j.entries()[0].contentBefore), "# TODO: write docs")
        // 文件已被实际修改
        @Expect(String.fromUtf8(File.readFrom(p)), "# 待办: write docs")
        // 通过 journal undo 应可恢复
        match (j.popLast()) {
            case Some(s) => j.revert(s)
            case None => @Fail("expected snapshot")
        }
        @Expect(String.fromUtf8(File.readFrom(p)), "# TODO: write docs")
    }

    @TestCase
    func writeFileToolRecordsSnapshotForNewFile() {
        let dir = tmpJournalDir()
        let p = dir.join("new").join("created.txt")
        let j = FileJournal()
        let tool = WriteFileTool(j)
        let args = jsonPath(p.toString(), "\"content\":\"hello\"")
        let r = tool.execute(args)
        @Expect(r.isError, false)
        @Expect(j.size(), 1)
        @Expect(j.entries()[0].existedBefore, false)
        @Expect(exists(p), true)
        // /undo 应当让文件再次消失
        match (j.popLast()) {
            case Some(s) => j.revert(s)
            case None => @Fail("expected snapshot")
        }
        @Expect(exists(p), false)
    }

    @TestCase
    func summaryDeduplicatesByPath() {
        let dir = tmpJournalDir()
        let p = dir.join("multi.txt")
        File.writeTo(p, "v0".toArray())
        let j = FileJournal()
        // 多次记录同一文件 — summary 只应出现一次
        j.record(p.toString(), "edit_file")
        File.writeTo(p, "v1".toArray())
        j.record(p.toString(), "edit_file")
        File.writeTo(p, "v22-final".toArray())
        let s = j.summary()
        @Expect(s.size, 1)
        let (path, beforeB, nowB, existedBefore, existsNow) = s[0]
        @Expect(path, p.toString())
        @Expect(beforeB, 2) // "v0" 长度
        @Expect(nowB, 9) // "v22-final" 长度
        @Expect(existedBefore, true)
        @Expect(existsNow, true)
    }

    @TestCase
    func clearEmptiesStack() {
        let j = FileJournal()
        j.record("/tmp/cj_x", "edit_file")
        j.record("/tmp/cj_y", "write_file")
        @Expect(j.size(), 2)
        j.clear()
        @Expect(j.size(), 0)
    }

    @TestCase
    func backwardCompatToolsWithoutJournal() {
        // 旧的零参数构造函数仍然可用（向后兼容，便于既有单元测试不破）
        let dir = tmpJournalDir()
        let p = dir.join("legacy.txt")
        File.writeTo(p, "abc".toArray())
        let edit = EditFileTool()
        let r = edit.execute(jsonPath(p.toString(), "\"old_str\":\"a\",\"new_str\":\"A\""))
        @Expect(r.isError, false)
        @Expect(String.fromUtf8(File.readFrom(p)), "Abc")
    }
}
