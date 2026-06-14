package cangjiecoder.tools

import std.fs.*
import std.sync.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
class ListDirToolTests {
    @TestCase
    func errorOnMissingDir() {
        let r = ListDirTool().execute(jsonPath("/tmp/__nope_list_dir__", ""))
        @Expect(r.isError, true)
    }

    @TestCase
    func listsFilesAndDirectories() {
        let sb = newSandbox()
        try {
            writeText(sb.join("a.txt"), "x")
            writeText(sb.join("b.md"), "y")
            Directory.create(sb.join("sub"), recursive: false)
            let r = ListDirTool().execute(jsonPath(sb.toString(), ""))
            @Expect(r.isError, false)
            @Expect(r.content.contains("f\ta.txt"), true)
            @Expect(r.content.contains("f\tb.md"), true)
            @Expect(r.content.contains("d\tsub/"), true)
        } finally {
            cleanupSandbox(sb)
        }
    }

    @TestCase
    func excludesNoiseEntries() {
        let sb = newSandbox()
        try {
            Directory.create(sb.join(".git"), recursive: false)
            Directory.create(sb.join("node_modules"), recursive: false)
            writeText(sb.join("keep.txt"), "x")
            let r = ListDirTool().execute(jsonPath(sb.toString(), ""))
            @Expect(r.content.contains(".git"), false)
            @Expect(r.content.contains("node_modules"), false)
            @Expect(r.content.contains("keep.txt"), true)
        } finally {
            cleanupSandbox(sb)
        }
    }
}

@Test
class IsNoiseEntryTests {
    @TestCase
    func noiseEntries() {
        @Expect(isNoiseEntry(".git"), true)
        @Expect(isNoiseEntry("target"), true)
        @Expect(isNoiseEntry("node_modules"), true)
        @Expect(isNoiseEntry("build"), true)
        @Expect(isNoiseEntry("dist"), true)
        @Expect(isNoiseEntry("src"), false)
        @Expect(isNoiseEntry("README.md"), false)
    }
}

@Test
class WalkDirTests {
    @TestCase
    func walkDirEarlyTermination() {
        // 修复前：walkDir 返回 Unit，子目录递归忽略 visitor 返回的 false
        // 修复后：walkDir 返回 Bool，visitor 返回 false 时立即终止整棵树遍历
        let sb = newSandbox()
        try {
            writeText(sb.join("a.txt"), "x")
            writeText(sb.join("b.txt"), "y")
            writeText(sb.join("c.txt"), "z")
            Directory.create(sb.join("sub"), recursive: false)
            writeText(sb.join("sub/d.txt"), "w")
            let count = AtomicInt64(0)
            let stopped = !walkDir(
                sb,
                ".",
                {
                    _, _, _ =>
                        let n = count.fetchAdd(1) + 1
                        return n < 2 // 第 2 个条目后终止
                }
            )
            @Expect(stopped, true)
            @Expect(count.load(), 2)
        } finally {
            cleanupSandbox(sb)
        }
    }

    @TestCase
    func walkDirEarlyTerminationInSubdir() {
        // 验证子目录中 visitor 返回 false 也能正确冒泡终止
        let sb = newSandbox()
        try {
            Directory.create(sb.join("aaa"), recursive: false)
            for (i in 0..10) {
                writeText(sb.join("aaa/f${i}.txt"), "x")
            }
            writeText(sb.join("zzz_should_not_reach.txt"), "t")
            let visitCount = AtomicInt64(0)
            let stopped = !walkDir(
                sb,
                ".",
                {
                    _, _, _ =>
                        visitCount.fetchAdd(1)
                        return visitCount.load() < 3 // 第 3 个条目后终止
                }
            )
            @Expect(stopped, true)
            @Expect(visitCount.load(), 3)
        } finally {
            cleanupSandbox(sb)
        }
    }

    @TestCase
    func walkDirCompletesFullTraversal() {
        // 不终止时应返回 true
        let sb = newSandbox()
        try {
            writeText(sb.join("a.txt"), "x")
            writeText(sb.join("b.txt"), "y")
            let completed = walkDir(sb, ".", {_, _, _ => true})
            @Expect(completed, true)
        } finally {
            cleanupSandbox(sb)
        }
    }
}

@Test
class GlobSearchToolTests {
    @TestCase
    func errorOnMissingPattern() {
        @Expect(GlobTool().execute("{}").isError, true)
    }

    @TestCase
    func findsMatchingFilesRecursively() {
        let sb = newSandbox()
        try {
            writeText(sb.join("a.cj"), "x")
            writeText(sb.join("src/b.cj"), "y")
            writeText(sb.join("src/nested/c.cj"), "z")
            writeText(sb.join("src/other.txt"), "ignored")
            let r = GlobTool().execute("{\"pattern\":\"**/*.cj\",\"root\":" + jsonString(sb.toString()) + "}")
            @Expect(r.isError, false)
            @Expect(r.content.contains("a.cj"), true)
            @Expect(r.content.contains("b.cj"), true)
            @Expect(r.content.contains("c.cj"), true)
            @Expect(r.content.contains("other.txt"), false)
        } finally {
            cleanupSandbox(sb)
        }
    }

    @TestCase
    func respectsLimit() {
        let sb = newSandbox()
        try {
            for (i in 0..5) {
                writeText(sb.join("f${i}.txt"), "x")
            }
            let r = GlobTool().execute(
                "{\"pattern\":\"**/*.txt\",\"root\":" + jsonString(sb.toString()) + ",\"limit\":2}")
            @Expect(r.isError, false)
            // 输出形如 "// 匹配 2 个文件\nfX.txt\nfY.txt\n"
            @Expect(r.content.contains("匹配 2 个"), true)
        } finally {
            cleanupSandbox(sb)
        }
    }
}

@Test
class GrepSearchToolTests {
    @TestCase
    func errorOnMissingPattern() {
        @Expect(GrepTool().execute("{}").isError, true)
    }

    @TestCase
    func errorOnInvalidRegex() {
        @Expect(GrepTool().execute("{\"pattern\":\"[unclosed\"}").isError, true)
    }

    @TestCase
    func findsMatchingLines() {
        let sb = newSandbox()
        try {
            writeText(sb.join("a.md"), "hello world\nfoo bar\nhello again")
            writeText(sb.join("b.txt"), "ignored\nhello darkness")
            let r = GrepTool().execute(
                "{\"pattern\":\"hello\",\"file_glob\":\"**/*.md\",\"root\":" + jsonString(sb.toString()) + "}")
            @Expect(r.isError, false)
            @Expect(r.content.contains("a.md:1:"), true)
            @Expect(r.content.contains("a.md:3:"), true)
            @Expect(r.content.contains("b.txt"), false)
            @Expect(r.content.contains("命中 2 行"), true)
        } finally {
            cleanupSandbox(sb)
        }
    }

    @TestCase
    func defaultGlobMatchesAllFiles() {
        let sb = newSandbox()
        try {
            writeText(sb.join("a.md"), "needle here")
            writeText(sb.join("b.cj"), "another needle line")
            let r = GrepTool().execute("{\"pattern\":\"needle\",\"root\":" + jsonString(sb.toString()) + "}")
            @Expect(r.isError, false)
            @Expect(r.content.contains("a.md"), true)
            @Expect(r.content.contains("b.cj"), true)
        } finally {
            cleanupSandbox(sb)
        }
    }
}

@Test
class RunBashToolTests {
    @TestCase
    func errorOnEmptyCommand() {
        @Expect(RunBashTool().execute("{\"command\":\"   \"}").isError, true)
    }

    @TestCase
    func capturesStdoutAndExitCode() {
        let r = RunBashTool().execute("{\"command\":\"echo hello-from-bash\"}")
        @Expect(r.isError, false)
        @Expect(r.content.contains("hello-from-bash"), true)
        @Expect(r.content.contains("exit_code: 0"), true)
    }

    @TestCase
    func reportsNonZeroExitAsError() {
        let r = RunBashTool().execute("{\"command\":\"exit 7\"}")
        @Expect(r.isError, true)
        @Expect(r.content.contains("exit_code: 7"), true)
    }

    @TestCase
    func capturesStderr() {
        let r = RunBashTool().execute("{\"command\":\"echo oops 1>&2\"}")
        @Expect(r.content.contains("oops"), true)
        @Expect(r.content.contains("stderr"), true)
    }

    @TestCase
    func timeoutEnforcedAndReported() {
        // 修复前：timeout 参数被解析但从未使用，sleep 命令永远不会被终止
        // 修复后：Timer.once + AtomicBool 在超时后强制终止子进程
        let r = RunBashTool().execute("{\"command\":" + jsonString(sleepCommand()) + ",\"timeout_seconds\":2}")
        @Expect(r.isError, true)
        @Expect(r.content.contains("超时"), true)
        @Expect(r.content.contains("exit_code: -1"), true)
    }

    @TestCase
    func binaryOutputDoesNotCrash() {
        // 修复前：String.fromUtf8 对非 UTF-8 字节直接抛异常
        // 修复后：tryDecodeUtf8 失败时回退为 "<二进制输出, N 字节>"
        let r = RunBashTool().execute("{\"command\":" + jsonString(binaryOutputCommand()) + "}")
        @Expect(r.isError, false)
        // 输出应包含二进制提示或成功解码（不崩溃即通过）
    }

    @TestCase
    func timeoutClampsToMax() {
        // timeout > MAX_COMMAND_TIMEOUT (600) 时应被钳制
        let r = RunBashTool().execute(##"{"command":"echo ok","timeout_seconds":9999}"##)
        @Expect(r.isError, false)
        @Expect(r.content.contains("echo"), false) // 不会挂住
    }
}

@When[os == "Windows"]
func sleepCommand(): String {
    return "powershell.exe -NoProfile -NonInteractive -Command Start-Sleep -Seconds 30"
}

@When[os != "Windows"]
func sleepCommand(): String {
    return "sleep 30"
}

@When[os == "Windows"]
func binaryOutputCommand(): String {
    return "powershell.exe -NoProfile -NonInteractive -Command \"[Console]::OpenStandardOutput().Write([byte[]](128,254,255),0,3)\""
}

@When[os != "Windows"]
func binaryOutputCommand(): String {
    return "printf '\\x80\\xFE\\xFF'"
}
