package cangjiecoder.tools

import std.fs.*
import std.env.*
import std.sync.*
import std.time.*

/**
 * 测试沙箱：在 /tmp 下生成一个独立目录用于文件类工具测试，
 * 互不影响、便于清理
 *
 * 注意：仓颉标准库目前没有 `setCurrentDirectory`，因此调用工具时一律
 * 使用绝对路径而不是依赖 CWD
 */
let g_sandboxCounter = AtomicInt64(0)

public func newSandbox(): Path {
    let n = g_sandboxCounter.fetchAdd(1) + 1
    let nanos = DateTime.nowUTC().toUnixTimeStamp().toNanoseconds()
    let root = testTempRoot().join("cangjiecoder_test_${nanos}_${n}")
    Directory.create(root, recursive: true)
    return root
}

@When[os == "Windows"]
func testTempRoot(): Path {
    let temp = getVariable("TEMP") ?? (getVariable("TMP") ?? "C:\\tmp")
    return Path(temp)
}

@When[os != "Windows"]
func testTempRoot(): Path {
    return Path("/tmp")
}

public func cleanupSandbox(p: Path): Unit {
    if (exists(p)) {
        try {
            remove(p, recursive: true)
        } catch (_: Exception) {}
    }
}

public func writeText(p: Path, content: String): Unit {
    let parent = p.parent
    if (!parent.toString().isEmpty() && !exists(parent)) {
        Directory.create(parent, recursive: true)
    }
    File.writeTo(p, content.toArray())
}

public func readText(p: Path): String {
    return String.fromUtf8(File.readFrom(p))
}

public func jsonString(s: String): String {
    return "\"" + s
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t") + "\""
}

public func jsonPath(path: String, extra: String): String {
    if (extra.isEmpty()) {
        return "{\"path\":" + jsonString(path) + "}"
    }
    return "{\"path\":" + jsonString(path) + "," + extra + "}"
}
