package cangjiecoder.httpx

import std.collection.*
import std.fs.*
import std.sync.*
import std.time.*
import std.unittest.*
import std.unittest.testmacro.*

let g_clientSandboxCounter = AtomicInt64(0)

func newTempDir(): Path {
    let counter = g_clientSandboxCounter.fetchAdd(1) + 1
    let nanos = DateTime.nowUTC().toUnixTimeStamp().toNanoseconds()
    let root = Path("/tmp/cangjiecoder_httpx_${nanos}_${counter}")
    Directory.create(root, recursive: true)
    return root
}

func cleanupDir(p: Path) {
    if (exists(p)) {
        try { remove(p, recursive: true) } catch (_: Exception) {}
    }
}

@Test
class ReadPemFileTests {
    @TestCase
    func returnsContentForValidFile() {
        let dir = newTempDir()
        try {
            let pemPath = dir.join("test.pem")
            let content = "-----BEGIN CERTIFICATE-----\nMIIBxTCCAW...\n-----END CERTIFICATE-----\n"
            File.writeTo(pemPath, content.toArray())
            match (readPemFile(pemPath.toString())) {
                case Some(result) =>
                    @Expect(result, content)
                case None =>
                    @Fail("expected Some, got None")
            }
        } finally {
            cleanupDir(dir)
        }
    }

    @TestCase
    func returnsNoneForNonexistentFile() {
        let result = readPemFile("/tmp/nonexistent_pem_file_12345.pem")
        @Expect(result.isNone(), true)
    }

    @TestCase
    func returnsNoneForInvalidUtf8() {
        let dir = newTempDir()
        try {
            let badPath = dir.join("bad.pem")
            // 写入非法 UTF-8 字节序列
            let badBytes: Array<Byte> = [0x80u8, 0xFEu8, 0xFFu8]
            File.writeTo(badPath, badBytes)
            let result = readPemFile(badPath.toString())
            @Expect(result.isNone(), true)
        } finally {
            cleanupDir(dir)
        }
    }

    @TestCase
    func continueSkipsNoneInLoop() {
        // 验证 ?? continue 行为：当 readPemFile 返回 None 时，循环跳过后续逻辑
        var processed = 0
        let paths = ["/tmp/nonexistent_pem_1.pem", "/tmp/nonexistent_pem_2.pem"]
        for (path in paths) {
            let _ = readPemFile(path) ?? continue
            processed++
        }
        @Expect(processed, 0)
    }

    @TestCase
    func continueOnlySkipsNone() {
        // 验证 ?? continue 行为：当 readPemFile 返回 Some 时，正常处理
        let dir = newTempDir()
        try {
            let validPath = dir.join("valid.pem")
            File.writeTo(validPath, "PEM CONTENT".toArray())
            var processed = 0
            let paths = ["/tmp/nonexistent_pem_3.pem", validPath.toString()]
            for (path in paths) {
                let _ = readPemFile(path) ?? continue
                processed++
            }
            @Expect(processed, 1)
        } finally {
            cleanupDir(dir)
        }
    }
}

@Test
class DecodeLineTests {
    @TestCase
    func emptyBytesReturnsEmptyString() {
        let bytes = ArrayList<Byte>()
        @Expect(decodeLine(bytes), "")
    }

    @TestCase
    func asciiBytes() {
        let bytes = ArrayList<Byte>()
        for (b in "hello".toArray()) { bytes.add(b) }
        @Expect(decodeLine(bytes), "hello")
    }

    @TestCase
    func cjkMultiByteBytes() {
        // CJK 字符 "你好" 在 UTF-8 中是 6 字节
        // 这正是 SSE 修复要解决的问题：确保完整行的多字节字符正确解码
        let bytes = ArrayList<Byte>()
        for (b in "你好世界".toArray()) { bytes.add(b) }
        @Expect(decodeLine(bytes), "你好世界")
    }

    @TestCase
    func mixedAsciiAndCjk() {
        let bytes = ArrayList<Byte>()
        for (b in "data: 你好".toArray()) { bytes.add(b) }
        @Expect(decodeLine(bytes), "data: 你好")
    }
}