package cangjiecoder.common

import std.unittest.*
import std.unittest.testmacro.*

@Test
class TruncateUtf8Tests {
    @TestCase
    func shortStringUnchanged() {
        let s = "hello"
        @Assert(truncateUtf8(s, 10), s)
    }

    @TestCase
    func asciiTruncation() {
        let s = "abcdefghij"
        @Assert(truncateUtf8(s, 5), "abcde")
    }

    @TestCase
    func emptyString() {
        @Assert(truncateUtf8("", 10), "")
    }

    @TestCase
    func cjkNotSplit() {
        let s = "abc\u{4F60}\u{597D}"
        @Assert(truncateUtf8(s, 5), "abc")
    }

    @TestCase
    func cjkExactBoundary() {
        let s = "abc\u{4F60}\u{597D}"
        @Assert(truncateUtf8(s, 6), "abc\u{4F60}")
    }

    @TestCase
    func cjkFullString() {
        let s = "abc\u{4F60}\u{597D}"
        @Assert(truncateUtf8(s, 9), s)
    }

    @TestCase
    func pureCjkTruncation() {
        let s = "\u{4F60}\u{597D}\u{4E16}\u{754C}"
        @Assert(truncateUtf8(s, 7), "\u{4F60}\u{597D}")
    }

    @TestCase
    func maxBytesLargerThanString() {
        let s = "short"
        @Assert(truncateUtf8(s, 100), s)
    }

    @TestCase
    func maxBytesZero() {
        @Assert(truncateUtf8("hello", 0), "")
    }
}

@Test
class TruncateHeadTailTests {
    @TestCase
    func shortOutputUnchanged() {
        let s = "hello world"
        @Assert(truncateHeadTail(s, 100), s)
    }

    @TestCase
    func longOutputIsTruncatedWithMiddleOmission() {
        let sb = StringBuilder()
        for (_ in 0..200) {
            sb.append("abcde")
        }
        let s = sb.toString()
        let result = truncateHeadTail(s, 100)
        @Expect(result.contains("省略"), true)
        @Expect(result.startsWith("abcde"), true)
    }

    @TestCase
    func cjkTruncateDoesNotBreakCharacters() {
        let sb = StringBuilder()
        for (_ in 0..200) {
            sb.append("你好世界")
        }
        let s = sb.toString()
        let result = truncateHeadTail(s, 100)
        @Expect(result.contains("省略"), true)
        @Expect(result.size > 0, true)
    }
}
