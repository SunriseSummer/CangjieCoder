package cangjiecoder.tools

import std.unittest.*
import std.unittest.testmacro.*

@Test
class ArgsParserTests {
    @TestCase
    func parsesEmptyAsEmptyObject() {
        let obj = parseArgs("")
        @Expect(obj.size(), 0)
    }

    @TestCase
    func parsesWhitespaceAsEmpty() {
        let obj = parseArgs("   ")
        @Expect(obj.size(), 0)
    }

    @TestCase
    func parsesNonObjectAsEmpty() {
        @Expect(parseArgs("[]").size(), 0)
        @Expect(parseArgs("42").size(), 0)
        @Expect(parseArgs("\"x\"").size(), 0)
    }

    @TestCase
    func getStringHandlesAllScalarTypes() {
        let obj = parseArgs(##"{"s":"hi","i":42,"b":true,"f":1.5}"##)
        @Expect(getString(obj, "s"), "hi")
        @Expect(getString(obj, "i"), "42")
        @Expect(getString(obj, "b"), "true")
        @Expect(getString(obj, "missing"), "")
        @Expect(getString(obj, "missing", default: "fallback"), "fallback")
    }

    @TestCase
    func getStringReturnsDefaultForObject() {
        let obj = parseArgs(##"{"x":{"nested":1}}"##)
        @Expect(getString(obj, "x", default: "def"), "def")
    }

    @TestCase
    func getIntHandlesNumberAndString() {
        let obj = parseArgs(##"{"a":7,"b":"42","c":"abc"}"##)
        @Expect(getInt(obj, "a"), 7)
        @Expect(getInt(obj, "b"), 42)
        @Expect(getInt(obj, "c", default: -1), -1)
        @Expect(getInt(obj, "missing", default: 100), 100)
    }

    @TestCase
    func getPositiveIntFallsBackWhenNotPositive() {
        let obj = parseArgs(##"{"ok":3,"zero":0,"neg":-1}"##)
        @Expect(getPositiveInt(obj, "ok", default: 9), 3)
        @Expect(getPositiveInt(obj, "zero", default: 9), 9)
        @Expect(getPositiveInt(obj, "neg", default: 9), 9)
        @Expect(getPositiveInt(obj, "missing", default: 9), 9)
    }

    @TestCase
    func parsesMalformedJsonGracefully() {
        // 修复前：JsonValue.fromStr 直接抛异常导致 crash
        // 修复后：try-catch 返回空对象
        @Expect(parseArgs("{broken json").size(), 0)
        @Expect(parseArgs("{\"key\": }").size(), 0)
        @Expect(parseArgs("not json at all").size(), 0)
        @Expect(parseArgs("{\"a\":1,}").size(), 0) // 尾逗号
    }

    @TestCase
    func getBoolHandlesBoolAndString() {
        let obj = parseArgs(##"{"a":true,"b":false,"c":"true","d":"no"}"##)
        @Expect(getBool(obj, "a"), true)
        @Expect(getBool(obj, "b"), false)
        @Expect(getBool(obj, "c"), true)
        @Expect(getBool(obj, "d"), false)
        @Expect(getBool(obj, "missing", default: true), true)
    }

    @TestCase
    func requireStringRejectsMissingOrEmpty() {
        let obj = parseArgs(##"{"name":"deepseek","empty":""}"##)
        @Expect(requireString(obj, "name").isSome(), true)
        @Expect(requireString(obj, "empty").isNone(), true)
        @Expect(requireString(obj, "missing").isNone(), true)
    }
}
