package cangjiecoder.tools

import std.unittest.*
import std.unittest.testmacro.*

@Test
class TextEncodingTest {
    @TestCase
    func testUtf8PassThrough(): Unit {
        let bytes: Array<Byte> = [0x68, 0x69] // "hi"
        @Expect(decodeTextLenient(bytes), Some("hi"))
    }

    @TestCase
    func testGbkDecodeHello(): Unit {
        // GBK 编码的 "你好" = C4 E3 BA C3
        let bytes: Array<Byte> = [0xC4, 0xE3, 0xBA, 0xC3]
        @Expect(decodeGbk(bytes), Some("你好"))
    }

    @TestCase
    func testGbkAsciiPassThrough(): Unit {
        // ASCII 字节在 GBK 解码下应原样直通
        let bytes: Array<Byte> = [0x41, 0x42, 0x43] // "ABC"
        @Expect(decodeGbk(bytes), Some("ABC"))
    }

    @TestCase
    func testGbkMixed(): Unit {
        // "a你b" => 0x61, C4E3(你), 0x62
        let bytes: Array<Byte> = [0x61, 0xC4, 0xE3, 0x62]
        @Expect(decodeGbk(bytes), Some("a你b"))
    }

    @TestCase
    func testGbkDanglingLead(): Unit {
        // 悬挂首字节（无尾字节）应判定为非 GBK
        let bytes: Array<Byte> = [0x41, 0xC4]
        @Expect(decodeGbk(bytes), None)
    }

    @TestCase
    func testGbkInvalidTrail(): Unit {
        // 首字节合法但尾字节非法（0x20 不在 GBK 尾字节范围）
        let bytes: Array<Byte> = [0xC4, 0x20]
        @Expect(decodeGbk(bytes), None)
    }

    @TestCase
    func testBinaryRejected(): Unit {
        // 含 0x00/0xFF 等字节的二进制内容无法按 GBK 解码
        let bytes: Array<Byte> = [0xFF, 0x00, 0xFE]
        @Expect(decodeGbk(bytes), None)
    }
}
