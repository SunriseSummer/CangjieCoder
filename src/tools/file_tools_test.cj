package cangjiecoder.tools

import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*

/** 文件类工具的单元测试 */

@Test
class ReadFileToolTests {
    @TestCase
    func errorOnMissingPath() {
        let r = ReadFileTool().execute("{}")
        @Expect(r.isError, true)
    }

    @TestCase
    func errorOnNonexistentFile() {
        let r = ReadFileTool().execute(jsonPath("/tmp/__nope_definitely_not_real__", ""))
        @Expect(r.isError, true)
        @Expect(r.content.contains("不存在"), true)
    }

    @TestCase
    func readsWholeFileWithLineNumbers() {
        let sb = newSandbox()
        try {
            let f = sb.join("a.txt")
            writeText(f, "alpha\nbeta\ngamma")
            let r = ReadFileTool().execute(jsonPath(f.toString(), ""))
            @Expect(r.isError, false)
            @Expect(r.content.contains("alpha"), true)
            @Expect(r.content.contains("beta"), true)
            @Expect(r.content.contains("gamma"), true)
            @Expect(r.content.contains("1\talpha"), true)
            @Expect(r.content.contains("3\tgamma"), true)
            @Expect(r.content.contains("总行数"), true)
        } finally {
            cleanupSandbox(sb)
        }
    }

    @TestCase
    func startAndLimitWindow() {
        let sb = newSandbox()
        try {
            let f = sb.join("multi.txt")
            writeText(f, "L1\nL2\nL3\nL4\nL5\nL6")
            let r = ReadFileTool().execute(jsonPath(f.toString(), "\"start_line\":2,\"limit_lines\":2"))
            @Expect(r.isError, false)
            @Expect(r.content.contains("2\tL2"), true)
            @Expect(r.content.contains("3\tL3"), true)
            @Expect(r.content.contains("L4"), false)
            @Expect(r.content.contains("还有"), true)
        } finally {
            cleanupSandbox(sb)
        }
    }

    @TestCase
    func startBeyondEnd() {
        let sb = newSandbox()
        try {
            let f = sb.join("short.txt")
            writeText(f, "only-one-line")
            let r = ReadFileTool().execute(jsonPath(f.toString(), "\"start_line\":100"))
            @Expect(r.isError, false)
            @Expect(r.content.contains("超出范围"), true)
        } finally {
            cleanupSandbox(sb)
        }
    }

    @TestCase
    func limitOneReadsOnlyOneLine() {
        let sb = newSandbox()
        try {
            let f = sb.join("multi.txt")
            writeText(f, "L1\nL2\nL3\nL4")
            let r = ReadFileTool().execute(jsonPath(f.toString(), "\"start_line\":2,\"limit_lines\":1"))
            @Expect(r.isError, false)
            @Expect(r.content.contains("2\tL2"), true)
            @Expect(r.content.contains("3\tL3"), false)
        } finally {
            cleanupSandbox(sb)
        }
    }

    @TestCase
    func readsCjkContent() {
        let sb = newSandbox()
        try {
            let f = sb.join("cjk.txt")
            writeText(f, "你好\n世界\n仓颉")
            let r = ReadFileTool().execute(jsonPath(f.toString(), ""))
            @Expect(r.isError, false)
            @Expect(r.content.contains("你好"), true)
            @Expect(r.content.contains("世界"), true)
            @Expect(r.content.contains("仓颉"), true)
        } finally {
            cleanupSandbox(sb)
        }
    }
}

@Test
class WriteFileToolTests {
    @TestCase
    func errorOnMissingPath() {
        @Expect(WriteFileTool().execute("{\"content\":\"x\"}").isError, true)
    }

    @TestCase
    func createsNewFileAndReportsCreated() {
        let sb = newSandbox()
        try {
            let f = sb.join("new.txt")
            let r = WriteFileTool().execute(jsonPath(f.toString(), "\"content\":\"hello\""))
            @Expect(r.isError, false)
            @Expect(r.content.contains("已创建"), true)
            @Expect(readText(f), "hello")
        } finally {
            cleanupSandbox(sb)
        }
    }

    @TestCase
    func overwritesExistingFileAndReportsWritten() {
        let sb = newSandbox()
        try {
            let f = sb.join("existing.txt")
            writeText(f, "old")
            let r = WriteFileTool().execute(jsonPath(f.toString(), "\"content\":\"new\""))
            @Expect(r.isError, false)
            @Expect(r.content.contains("已写入"), true)
            @Expect(readText(f), "new")
        } finally {
            cleanupSandbox(sb)
        }
    }

    @TestCase
    func refusesOverwriteWhenDisabled() {
        let sb = newSandbox()
        try {
            let f = sb.join("guard.txt")
            writeText(f, "keep")
            let r = WriteFileTool().execute(jsonPath(f.toString(), "\"content\":\"x\",\"overwrite\":false"))
            @Expect(r.isError, true)
            @Expect(readText(f), "keep")
        } finally {
            cleanupSandbox(sb)
        }
    }

    @TestCase
    func createsParentDirectoriesRecursively() {
        let sb = newSandbox()
        try {
            let f = sb.join("a/b/c/deep.txt")
            let r = WriteFileTool().execute(jsonPath(f.toString(), "\"content\":\"deep\""))
            @Expect(r.isError, false)
            @Expect(exists(f), true)
        } finally {
            cleanupSandbox(sb)
        }
    }
}

@Test
class EditFileToolTests {
    @TestCase
    func errorOnMissingArgs() {
        @Expect(EditFileTool().execute("{}").isError, true)
    }

    @TestCase
    func errorOnNonexistentFile() {
        let r = EditFileTool().execute(jsonPath("/tmp/__nope_edit__", "\"old_str\":\"a\",\"new_str\":\"b\""))
        @Expect(r.isError, true)
    }

    @TestCase
    func replacesUniqueOccurrence() {
        let sb = newSandbox()
        try {
            let f = sb.join("code.txt")
            writeText(f, "let x = 1\nlet y = 2\n")
            let r = EditFileTool().execute(
                jsonPath(f.toString(), "\"old_str\":\"let x = 1\",\"new_str\":\"let x = 42\""))
            @Expect(r.isError, false)
            @Expect(readText(f), "let x = 42\nlet y = 2\n")
        } finally {
            cleanupSandbox(sb)
        }
    }

    @TestCase
    func errorWhenOldStrNotFound() {
        let sb = newSandbox()
        try {
            let f = sb.join("a.txt")
            writeText(f, "hello")
            let r = EditFileTool().execute(jsonPath(f.toString(), "\"old_str\":\"world\",\"new_str\":\"x\""))
            @Expect(r.isError, true)
            @Expect(r.content.contains("未在文件中匹配"), true)
        } finally {
            cleanupSandbox(sb)
        }
    }

    @TestCase
    func errorWhenOldStrAmbiguous() {
        let sb = newSandbox()
        try {
            let f = sb.join("a.txt")
            writeText(f, "foo\nfoo\nfoo")
            let r = EditFileTool().execute(jsonPath(f.toString(), "\"old_str\":\"foo\",\"new_str\":\"bar\""))
            @Expect(r.isError, true)
            @Expect(r.content.contains("3 次"), true)
            @Expect(readText(f), "foo\nfoo\nfoo")
        } finally {
            cleanupSandbox(sb)
        }
    }

    @TestCase
    func editCjkContent() {
        let sb = newSandbox()
        try {
            let f = sb.join("cjk.txt")
            writeText(f, "你好世界\n仓颉语言")
            let r = EditFileTool().execute(jsonPath(f.toString(), "\"old_str\":\"你好世界\",\"new_str\":\"你好仓颉\""))
            @Expect(r.isError, false)
            @Expect(readText(f), "你好仓颉\n仓颉语言")
        } finally {
            cleanupSandbox(sb)
        }
    }

    @TestCase
    func matchesAcrossCrlfWithLfOldStr() {
        // 文件为 CRLF（Windows 常见），模型给出的多行 old_str 用 LF
        // 应能匹配并替换，且保持文件原有的 CRLF 行尾风格
        let sb = newSandbox()
        try {
            let f = sb.join("crlf.py")
            writeText(f, "line1\r\nline2\r\nline3\r\n")
            let r = EditFileTool().execute(
                jsonPath(f.toString(), "\"old_str\":\"line1\\nline2\",\"new_str\":\"LINE1\\nLINE2\""))
            @Expect(r.isError, false)
            @Expect(readText(f), "LINE1\r\nLINE2\r\nline3\r\n")
        } finally {
            cleanupSandbox(sb)
        }
    }
}

@Test
class CountOccurrencesTests {
    @TestCase
    func basics() {
        @Expect(countOccurrences("aaaa", "a"), 4)
        @Expect(countOccurrences("aaaa", "aa"), 2)
        @Expect(countOccurrences("abcabc", "abc"), 2)
        @Expect(countOccurrences("hello", "xyz"), 0)
        @Expect(countOccurrences("anything", ""), 0)
    }

    @TestCase
    func cjkStringCounting() {
        // 中文字符串中匹配中文子串
        @Expect(countOccurrences("你好世界你好", "你好"), 2)
        @Expect(countOccurrences("abc你好abc", "abc"), 2)
        @Expect(countOccurrences("你好", "世界"), 0)
    }

    @TestCase
    func noOverlapForAdjacentMatches() {
        // "aaa" contains "aa" at position 0, next search starts at 2, no match
        @Expect(countOccurrences("aaa", "aa"), 1)
    }
}

@Test
class NormalizeNewlinesTests {
    @TestCase
    func convertsCrlfAndCrToLf() {
        @Expect(normalizeNewlines("a\r\nb\r\nc"), "a\nb\nc")
        @Expect(normalizeNewlines("a\rb\rc"), "a\nb\nc")
        @Expect(normalizeNewlines("a\nb\nc"), "a\nb\nc")
        @Expect(normalizeNewlines("plain"), "plain")
        @Expect(normalizeNewlines(""), "")
    }
}
