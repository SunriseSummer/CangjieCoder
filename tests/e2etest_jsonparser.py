#!/usr/bin/env python3
"""End-to-end test: AI-driven JsonParser project development via MCP tools.

This script replays a simulated AI coding session that develops a complete
JsonParser library in Cangjie — from project scaffolding to passing tests —
using **only** the MCP tool interface exposed by cangjiecoder.

The development flow mirrors what an AI agent would do:

  1. Search skills for JSON / project management knowledge
  2. Create a fresh workspace and initialise a cjpm project
  3. Iteratively create source files (model, lexer, parser, main)
  4. Analyse each file with AST tools after creation
  5. Build the project via workspace.run_build
  6. Create unit tests
  7. Run tests via workspace.run_test
  8. Verify the project works end-to-end

Running this script is a genuine end-to-end test of the MCP service:
every file operation, build, and analysis goes through the real service
binary over stdio.

Usage:
    python tests/e2etest_jsonparser.py [--bin PATH] [--keep]
"""

import argparse
import json
import os
import shutil
import sys
import tempfile

# ---------------------------------------------------------------------------
# Bootstrap – make sure we can import the shared MCP client
# ---------------------------------------------------------------------------
TESTS_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TESTS_DIR)
from mcp_client import McpClient  # noqa: E402

REPO_ROOT = os.path.dirname(TESTS_DIR)
DEFAULT_BIN = os.path.join(REPO_ROOT, "target", "release", "bin", "cangjiecoder")

# ---------------------------------------------------------------------------
# Source code that the "AI" will write — a complete JsonParser in Cangjie
# ---------------------------------------------------------------------------

CJPM_TOML = """\
[package]
name = "jsonparser"
version = "0.1.0"
cjc-version = "1.0.5"
output-type = "executable"
description = "A JSON parser library covering standard JSON syntax"
"""

# ── json_value.cj ── data model for JSON values
JSON_VALUE_CJ = r"""// JSON 值类型定义
package jsonparser

import std.collection.*
import std.deriving.*

// JSON 值类型枚举
@Derive[Equatable]
public enum JsonValueKind {
    | JNull
    | JBool
    | JNumber
    | JString
    | JArray
    | JObject
}

// JSON 值
public class JsonValue {
    public let kind: JsonValueKind
    var _boolVal: Bool
    var _numberVal: Float64
    var _stringVal: String
    var _arrayVal: ArrayList<JsonValue>
    var _objectKeys: ArrayList<String>
    var _objectVals: ArrayList<JsonValue>

    // 私有构造
    init(kind: JsonValueKind) {
        this.kind = kind
        _boolVal = false
        _numberVal = 0.0
        _stringVal = ""
        _arrayVal = ArrayList<JsonValue>()
        _objectKeys = ArrayList<String>()
        _objectVals = ArrayList<JsonValue>()
    }

    // 工厂方法
    public static func ofNull(): JsonValue {
        JsonValue(JsonValueKind.JNull)
    }

    public static func ofBool(v: Bool): JsonValue {
        let jv = JsonValue(JsonValueKind.JBool)
        jv._boolVal = v
        return jv
    }

    public static func ofNumber(v: Float64): JsonValue {
        let jv = JsonValue(JsonValueKind.JNumber)
        jv._numberVal = v
        return jv
    }

    public static func ofString(v: String): JsonValue {
        let jv = JsonValue(JsonValueKind.JString)
        jv._stringVal = v
        return jv
    }

    public static func ofArray(items: ArrayList<JsonValue>): JsonValue {
        let jv = JsonValue(JsonValueKind.JArray)
        jv._arrayVal = items
        return jv
    }

    public static func ofObject(keys: ArrayList<String>,
                                vals: ArrayList<JsonValue>): JsonValue {
        let jv = JsonValue(JsonValueKind.JObject)
        jv._objectKeys = keys
        jv._objectVals = vals
        return jv
    }

    // 访问器
    public func boolValue(): Bool { _boolVal }
    public func numberValue(): Float64 { _numberVal }
    public func stringValue(): String { _stringVal }
    public func arrayItems(): ArrayList<JsonValue> { _arrayVal }
    public func objectKeys(): ArrayList<String> { _objectKeys }
    public func objectValues(): ArrayList<JsonValue> { _objectVals }

    // 根据 key 取 object 子项
    public func get(key: String): ?JsonValue {
        var i = 0
        while (i < _objectKeys.size) {
            if (_objectKeys[i] == key) {
                return _objectVals[i]
            }
            i += 1
        }
        return None
    }

    // 简易 toString
    public func display(): String {
        match (kind) {
            case JNull => "null"
            case JBool => if (_boolVal) { "true" } else { "false" }
            case JNumber =>
                let n = _numberVal
                let i = Int64(n)
                if (Float64(i) == n) {
                    "${i}"
                } else {
                    "${n}"
                }
            case JString =>
                let q = "\""
                "${q}${_stringVal}${q}"
            case JArray =>
                var s = "["
                var idx = 0
                while (idx < _arrayVal.size) {
                    if (idx > 0) { s += ", " }
                    s += _arrayVal[idx].display()
                    idx += 1
                }
                s + "]"
            case JObject =>
                var s = "{"
                var idx = 0
                while (idx < _objectKeys.size) {
                    if (idx > 0) { s += ", " }
                    let q = "\""
                    s += "${q}${_objectKeys[idx]}${q}: ${_objectVals[idx].display()}"
                    idx += 1
                }
                s + "}"
        }
    }
}
"""

# ── json_lexer.cj ── tokenizer
JSON_LEXER_CJ = r"""// JSON 词法分析器
package jsonparser

import std.deriving.*

// Token 类型
@Derive[Equatable]
public enum TokenKind {
    | LBrace      // {
    | RBrace      // }
    | LBracket    // [
    | RBracket    // ]
    | Colon       // :
    | Comma       // ,
    | TString     // "..."
    | TNumber     // 数字
    | TTrue       // true
    | TFalse      // false
    | TNull       // null
    | TEof        // 输入结束
    | TError      // 错误
}

public class Token {
    public let kind: TokenKind
    public let value: String
    public init(kind: TokenKind, value: String) {
        this.kind = kind
        this.value = value
    }
}

// 词法分析器（基于 Rune 数组操作，正确处理 Unicode）
public class JsonLexer {
    let chars: Array<Rune>
    var pos: Int64

    public init(source: String) {
        this.chars = source.toRuneArray()
        this.pos = 0
    }

    func atEnd(): Bool {
        pos >= chars.size
    }

    func current(): Rune {
        chars[pos]
    }

    func advance(): Rune {
        let ch = chars[pos]
        pos += 1
        return ch
    }

    func skipWhitespace() {
        while (pos < chars.size) {
            let ch = chars[pos]
            if (ch == r' ' || ch == r'\t' || ch == r'\n' || ch == r'\r') {
                pos += 1
            } else {
                break
            }
        }
    }

    func readString(): Token {
        pos += 1 // skip opening "
        var result = ""
        while (pos < chars.size) {
            let ch = advance()
            if (ch == r'"') {
                return Token(TokenKind.TString, result)
            }
            if (ch == r'\\') {
                if (pos >= chars.size) {
                    return Token(TokenKind.TError, "Unexpected end of string escape")
                }
                let esc = advance()
                if (esc == r'"') {
                    result += "\""
                } else if (esc == r'\\') {
                    result += "\\"
                } else if (esc == r'/') {
                    result += "/"
                } else if (esc == r'n') {
                    result += "\n"
                } else if (esc == r't') {
                    result += "\t"
                } else if (esc == r'r') {
                    result += "\r"
                } else {
                    result += "\\"
                    result += esc.toString()
                }
            } else {
                result += ch.toString()
            }
        }
        return Token(TokenKind.TError, "Unterminated string")
    }

    func isDigit(ch: Rune): Bool {
        ch >= r'0' && ch <= r'9'
    }

    func readNumber(): Token {
        let start = pos
        if (pos < chars.size && chars[pos] == r'-') {
            pos += 1
        }
        while (pos < chars.size && isDigit(chars[pos])) {
            pos += 1
        }
        if (pos < chars.size && chars[pos] == r'.') {
            pos += 1
            while (pos < chars.size && isDigit(chars[pos])) {
                pos += 1
            }
        }
        if (pos < chars.size && (chars[pos] == r'e' || chars[pos] == r'E')) {
            pos += 1
            if (pos < chars.size && (chars[pos] == r'+' || chars[pos] == r'-')) {
                pos += 1
            }
            while (pos < chars.size && isDigit(chars[pos])) {
                pos += 1
            }
        }
        var numStr = ""
        var i = start
        while (i < pos) {
            numStr += chars[i].toString()
            i += 1
        }
        return Token(TokenKind.TNumber, numStr)
    }

    func matchKeyword(expected: String): Bool {
        let expectedRunes = expected.toRuneArray()
        if (pos + expectedRunes.size > chars.size) {
            return false
        }
        var i = 0
        while (i < expectedRunes.size) {
            if (chars[pos + i] != expectedRunes[i]) {
                return false
            }
            i += 1
        }
        pos += expectedRunes.size
        return true
    }

    public func nextToken(): Token {
        skipWhitespace()
        if (atEnd()) {
            return Token(TokenKind.TEof, "")
        }
        let ch = current()
        if (ch == r'{') { pos += 1; return Token(TokenKind.LBrace, "{") }
        if (ch == r'}') { pos += 1; return Token(TokenKind.RBrace, "}") }
        if (ch == r'[') { pos += 1; return Token(TokenKind.LBracket, "[") }
        if (ch == r']') { pos += 1; return Token(TokenKind.RBracket, "]") }
        if (ch == r':') { pos += 1; return Token(TokenKind.Colon, ":") }
        if (ch == r',') { pos += 1; return Token(TokenKind.Comma, ",") }
        if (ch == r'"') { return readString() }
        if (ch == r'-' || isDigit(ch)) { return readNumber() }
        if (matchKeyword("true"))  { return Token(TokenKind.TTrue, "true") }
        if (matchKeyword("false")) { return Token(TokenKind.TFalse, "false") }
        if (matchKeyword("null"))  { return Token(TokenKind.TNull, "null") }
        pos += 1
        return Token(TokenKind.TError, "Unexpected character: ${ch}")
    }
}
"""

# ── json_parser.cj ── recursive descent parser
JSON_PARSER_CJ = r"""// JSON 递归下降解析器
package jsonparser

import std.collection.*
import std.convert.*

// 解析结果
public class ParseResult {
    public let ok: Bool
    public let value: ?JsonValue
    public let error: String

    init(ok: Bool, value: ?JsonValue, error: String) {
        this.ok = ok
        this.value = value
        this.error = error
    }

    public static func success(v: JsonValue): ParseResult {
        ParseResult(true, v, "")
    }

    public static func failure(msg: String): ParseResult {
        ParseResult(false, None, msg)
    }
}

// 递归下降 JSON 解析器
public class JsonParser {
    var lexer: JsonLexer
    var current: Token

    public init(input: String) {
        lexer = JsonLexer(input)
        current = lexer.nextToken()
    }

    func advance() {
        current = lexer.nextToken()
    }

    func expect(kind: TokenKind): Bool {
        if (current.kind == kind) {
            advance()
            return true
        }
        return false
    }

    // 解析入口
    public func parse(): ParseResult {
        let result = parseValue()
        if (!result.ok) {
            return result
        }
        if (current.kind != TokenKind.TEof) {
            return ParseResult.failure("Unexpected content after JSON value")
        }
        return result
    }

    func parseValue(): ParseResult {
        match (current.kind) {
            case TNull =>
                advance()
                return ParseResult.success(JsonValue.ofNull())
            case TTrue =>
                advance()
                return ParseResult.success(JsonValue.ofBool(true))
            case TFalse =>
                advance()
                return ParseResult.success(JsonValue.ofBool(false))
            case TNumber =>
                let numStr = current.value
                advance()
                let num = Float64.parse(numStr)
                return ParseResult.success(JsonValue.ofNumber(num))
            case TString =>
                let s = current.value
                advance()
                return ParseResult.success(JsonValue.ofString(s))
            case LBracket => return parseArray()
            case LBrace => return parseObject()
            case TError =>
                return ParseResult.failure(current.value)
            case _ =>
                return ParseResult.failure("Unexpected token: ${current.value}")
        }
    }

    func parseArray(): ParseResult {
        advance() // skip [
        let items = ArrayList<JsonValue>()
        if (current.kind == TokenKind.RBracket) {
            advance()
            return ParseResult.success(JsonValue.ofArray(items))
        }
        while (true) {
            let elem = parseValue()
            if (!elem.ok) { return elem }
            match (elem.value) {
                case Some(v) => items.add(v)
                case None => return ParseResult.failure("Internal error: missing value")
            }
            if (current.kind == TokenKind.Comma) {
                advance()
            } else if (current.kind == TokenKind.RBracket) {
                advance()
                return ParseResult.success(JsonValue.ofArray(items))
            } else {
                return ParseResult.failure("Expected ',' or ']' in array")
            }
        }
        return ParseResult.failure("Unexpected end of array")
    }

    func parseObject(): ParseResult {
        advance() // skip {
        let keys = ArrayList<String>()
        let vals = ArrayList<JsonValue>()
        if (current.kind == TokenKind.RBrace) {
            advance()
            return ParseResult.success(JsonValue.ofObject(keys, vals))
        }
        while (true) {
            if (current.kind != TokenKind.TString) {
                return ParseResult.failure("Expected string key in object")
            }
            let key = current.value
            advance()
            if (!expect(TokenKind.Colon)) {
                return ParseResult.failure("Expected ':' after key")
            }
            let val = parseValue()
            if (!val.ok) { return val }
            keys.add(key)
            match (val.value) {
                case Some(v) => vals.add(v)
                case None => return ParseResult.failure("Internal error: missing value")
            }
            if (current.kind == TokenKind.Comma) {
                advance()
            } else if (current.kind == TokenKind.RBrace) {
                advance()
                return ParseResult.success(JsonValue.ofObject(keys, vals))
            } else {
                return ParseResult.failure("Expected ',' or '}' in object")
            }
        }
        return ParseResult.failure("Unexpected end of object")
    }
}

// 便捷入口函数
public func parseJson(input: String): ParseResult {
    JsonParser(input).parse()
}
"""

# ── main.cj ── demonstrate usage
MAIN_CJ = """\
// JsonParser 演示入口
package jsonparser

main() {
    // 解析一个完整的 JSON 对象
    let input = #"{"name": "CangjieCoder", "version": 1, "features": ["mcp", "ast"], "active": true}"#
    let result = parseJson(input)
    if (result.ok) {
        match (result.value) {
            case Some(v) => println("Parsed: ${v.display()}")
            case None => println("No value")
        }
    } else {
        println("Error: ${result.error}")
    }

    // 解析嵌套结构
    let nested = #"{"data": {"items": [1, 2, 3], "meta": null}}"#
    let r2 = parseJson(nested)
    if (r2.ok) {
        match (r2.value) {
            case Some(v) => println("Nested: ${v.display()}")
            case None => println("No value")
        }
    }

    // 解析各种基本类型
    let rNull = parseJson("null")
    println("null  => ${rNull.value.getOrThrow().display()}")
    let rTrue = parseJson("true")
    println("true  => ${rTrue.value.getOrThrow().display()}")
    let rFalse = parseJson("false")
    println("false => ${rFalse.value.getOrThrow().display()}")
    let r42 = parseJson("42")
    println("42    => ${r42.value.getOrThrow().display()}")
    let rPi = parseJson("3.14")
    println("3.14  => ${rPi.value.getOrThrow().display()}")
    let rStr = parseJson(#""hello""#)
    println("str   => ${rStr.value.getOrThrow().display()}")
    let rArr = parseJson("[]")
    println("[]    => ${rArr.value.getOrThrow().display()}")
    let rObj = parseJson("{}")
    println("{}    => ${rObj.value.getOrThrow().display()}")
}
"""

# ── json_parser_test.cj ── unit tests
JSON_PARSER_TEST_CJ = r"""// JsonParser 单元测试
package jsonparser

import std.unittest.*
import std.unittest.testmacro.*
import std.collection.*

@Test
class JsonParserTest {
    @TestCase
    func parseNull() {
        let r = parseJson("null")
        @Assert(r.ok)
        @Assert(r.value.getOrThrow().kind == JsonValueKind.JNull)
    }

    @TestCase
    func parseTrue() {
        let r = parseJson("true")
        @Assert(r.ok)
        @Assert(r.value.getOrThrow().boolValue() == true)
    }

    @TestCase
    func parseFalse() {
        let r = parseJson("false")
        @Assert(r.ok)
        @Assert(r.value.getOrThrow().boolValue() == false)
    }

    @TestCase
    func parseInteger() {
        let r = parseJson("42")
        @Assert(r.ok)
        @Assert(r.value.getOrThrow().numberValue() == 42.0)
    }

    @TestCase
    func parseNegativeNumber() {
        let r = parseJson("-7")
        @Assert(r.ok)
        @Assert(r.value.getOrThrow().numberValue() == -7.0)
    }

    @TestCase
    func parseFloat() {
        let r = parseJson("3.14")
        @Assert(r.ok)
        let n = r.value.getOrThrow().numberValue()
        @Assert(n > 3.13 && n < 3.15)
    }

    @TestCase
    func parseScientific() {
        let r = parseJson("1e3")
        @Assert(r.ok)
        @Assert(r.value.getOrThrow().numberValue() == 1000.0)
    }

    @TestCase
    func parseString() {
        let r = parseJson(#""hello""#)
        @Assert(r.ok)
        @Assert(r.value.getOrThrow().stringValue() == "hello")
    }

    @TestCase
    func parseStringWithEscapes() {
        let r = parseJson(#""line1\nline2""#)
        @Assert(r.ok)
        @Assert(r.value.getOrThrow().stringValue() == "line1\nline2")
    }

    @TestCase
    func parseEmptyArray() {
        let r = parseJson("[]")
        @Assert(r.ok)
        @Assert(r.value.getOrThrow().arrayItems().size == 0)
    }

    @TestCase
    func parseArray() {
        let r = parseJson("[1, 2, 3]")
        @Assert(r.ok)
        let items = r.value.getOrThrow().arrayItems()
        @Assert(items.size == 3)
        @Assert(items[0].numberValue() == 1.0)
        @Assert(items[2].numberValue() == 3.0)
    }

    @TestCase
    func parseMixedArray() {
        let r = parseJson(#"[1, "two", true, null]"#)
        @Assert(r.ok)
        let items = r.value.getOrThrow().arrayItems()
        @Assert(items.size == 4)
        @Assert(items[0].kind == JsonValueKind.JNumber)
        @Assert(items[1].kind == JsonValueKind.JString)
        @Assert(items[2].kind == JsonValueKind.JBool)
        @Assert(items[3].kind == JsonValueKind.JNull)
    }

    @TestCase
    func parseEmptyObject() {
        let r = parseJson("{}")
        @Assert(r.ok)
        @Assert(r.value.getOrThrow().objectKeys().size == 0)
    }

    @TestCase
    func parseObject() {
        let r = parseJson(#"{"a": 1, "b": "hello"}"#)
        @Assert(r.ok)
        let v = r.value.getOrThrow()
        @Assert(v.objectKeys().size == 2)
        match (v.get("a")) {
            case Some(a) => @Assert(a.numberValue() == 1.0)
            case None => @Assert(false)
        }
        match (v.get("b")) {
            case Some(b) => @Assert(b.stringValue() == "hello")
            case None => @Assert(false)
        }
    }

    @TestCase
    func parseNestedObject() {
        let r = parseJson(#"{"outer": {"inner": [1, 2]}}"#)
        @Assert(r.ok)
        let outer = r.value.getOrThrow()
        match (outer.get("outer")) {
            case Some(innerObj) =>
                match (innerObj.get("inner")) {
                    case Some(arr) =>
                        @Assert(arr.arrayItems().size == 2)
                    case None => @Assert(false)
                }
            case None => @Assert(false)
        }
    }

    @TestCase
    func parseWhitespace() {
        let r = parseJson(#"  {  "a"  :  1  }  "#)
        @Assert(r.ok)
    }

    @TestCase
    func parseErrorUnexpected() {
        let r = parseJson("invalid")
        @Assert(!r.ok)
    }

    @TestCase
    func parseErrorTrailing() {
        let r = parseJson("123 456")
        @Assert(!r.ok)
    }

    @TestCase
    func parseErrorUnclosedArray() {
        let r = parseJson("[1, 2")
        @Assert(!r.ok)
    }

    @TestCase
    func parseErrorUnclosedObject() {
        let r = parseJson(#"{"a": 1"#)
        @Assert(!r.ok)
    }

    @TestCase
    func displayNull() {
        @Assert(parseJson("null").value.getOrThrow().display() == "null")
    }

    @TestCase
    func displayBool() {
        @Assert(parseJson("true").value.getOrThrow().display() == "true")
        @Assert(parseJson("false").value.getOrThrow().display() == "false")
    }

    @TestCase
    func displayNumber() {
        @Assert(parseJson("42").value.getOrThrow().display() == "42")
    }

    @TestCase
    func displayArray() {
        let d = parseJson("[1, 2]").value.getOrThrow().display()
        @Assert(d == "[1, 2]")
    }
}
"""


# ---------------------------------------------------------------------------
# Test orchestration helpers
# ---------------------------------------------------------------------------

def step(msg):
    """Print a step banner."""
    print(f"\n{'─' * 60}")
    print(f"  🔧  {msg}")
    print(f"{'─' * 60}")


def check(condition, description, detail=""):
    """Assert a condition and record it."""
    if condition:
        print(f"  ✓ {description}")
    else:
        info = f": {detail}" if detail else ""
        print(f"  ✗ {description}{info}")
        raise AssertionError(f"FAILED: {description}{info}")


# ---------------------------------------------------------------------------
# Main e2e scenario
# ---------------------------------------------------------------------------

def run_e2e(service_bin, keep_workspace):
    """Execute the full JsonParser development scenario."""

    # Create a fresh temp workspace
    workspace = tempfile.mkdtemp(prefix="cjcoder_e2e_jsonparser_")
    print(f"\n  Workspace: {workspace}")

    passed = 0
    failed = 0
    errors = []

    def client():
        return McpClient(workspace=workspace, service_bin=service_bin)

    try:
        # ══════════════════════════════════════════════════════════
        # Phase 1: Knowledge gathering — search relevant skills
        # ══════════════════════════════════════════════════════════
        step("Phase 1: Search Cangjie skills for JSON and project setup knowledge")

        c = client()
        c.start()
        c.call_tool("skills.search", {"query": "JSON 解析"})         # 0
        c.call_tool("skills.search", {"query": "enum 枚举"})          # 1
        c.call_tool("skills.search", {"query": "单元测试 unittest"})   # 2
        c.call_tool("skills.search", {"query": "class 类定义"})        # 3
        resp = c.execute()

        for i, topic in enumerate(["JSON", "enum", "unittest", "class"]):
            ok = resp[i].get("ok") is True
            if ok:
                print(f"  ✓ skills.search({topic}) returned results")
                passed += 1
            else:
                print(f"  ✗ skills.search({topic}) failed")
                failed += 1
                errors.append(f"skills.search({topic})")

        # ══════════════════════════════════════════════════════════
        # Phase 2: Project scaffolding — create workspace files
        # ══════════════════════════════════════════════════════════
        step("Phase 2: Set workspace root and create project files")

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})          # 0
        c.call_tool("workspace.create_file", {                           # 1
            "path": "cjpm.toml",
            "content": CJPM_TOML
        })
        c.call_tool("workspace.create_file", {                           # 2
            "path": "src/json_value.cj",
            "content": JSON_VALUE_CJ
        })
        c.call_tool("workspace.create_file", {                           # 3
            "path": "src/json_lexer.cj",
            "content": JSON_LEXER_CJ
        })
        c.call_tool("workspace.create_file", {                           # 4
            "path": "src/json_parser.cj",
            "content": JSON_PARSER_CJ
        })
        c.call_tool("workspace.create_file", {                           # 5
            "path": "src/main.cj",
            "content": MAIN_CJ
        })
        c.call_tool("workspace.create_file", {                           # 6
            "path": "src/json_parser_test.cj",
            "content": JSON_PARSER_TEST_CJ
        })
        c.call_tool("workspace.list_files", {"path": "src"})             # 7
        resp = c.execute()

        file_names = ["cjpm.toml", "json_value.cj", "json_lexer.cj",
                       "json_parser.cj", "main.cj", "json_parser_test.cj"]
        for i, name in enumerate(file_names):
            ok = resp[i + 1].get("ok") is True
            if ok:
                print(f"  ✓ workspace.create_file({name})")
                passed += 1
            else:
                msg = resp[i + 1].get("message", "")
                print(f"  ✗ workspace.create_file({name}): {msg}")
                failed += 1
                errors.append(f"create_file({name})")

        # Verify file listing
        files_ok = resp[7].get("ok") is True
        file_count = resp[7].get("data", {}).get("count", 0) if files_ok else 0
        if files_ok and file_count >= 5:
            print(f"  ✓ workspace.list_files(src) found {file_count} files")
            passed += 1
        else:
            print(f"  ✗ workspace.list_files(src): count={file_count}")
            failed += 1
            errors.append("list_files")

        # ══════════════════════════════════════════════════════════
        # Phase 3: Code analysis — use AST tools to inspect code
        # ══════════════════════════════════════════════════════════
        step("Phase 3: Analyse created files with AST tools")

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("cangjie.ast_summary", {"path": "src/json_value.cj"})       # 1
        c.call_tool("cangjie.ast_summary", {"path": "src/json_lexer.cj"})       # 2
        c.call_tool("cangjie.ast_summary", {"path": "src/json_parser.cj"})      # 3
        c.call_tool("cangjie.ast_parse", {"path": "src/main.cj"})               # 4
        c.call_tool("cangjie.ast_query_nodes_with_text", {                       # 5
            "path": "src/json_parser.cj",
            "nodeType": "functionDefinition"
        })
        resp = c.execute()

        # ast_summary for json_value.cj — should detect JsonValueKind enum and JsonValue class
        summary_value = resp[1]
        sv_ok = summary_value.get("ok") is True
        sv_entries = summary_value.get("data", {}).get("entries", [])
        if sv_ok and len(sv_entries) > 0:
            print(f"  ✓ ast_summary(json_value.cj): {len(sv_entries)} entries")
            passed += 1
        else:
            print(f"  ✗ ast_summary(json_value.cj): ok={sv_ok}")
            failed += 1
            errors.append("ast_summary(json_value.cj)")

        # ast_summary for json_lexer.cj
        summary_lexer = resp[2]
        sl_ok = summary_lexer.get("ok") is True
        if sl_ok:
            print(f"  ✓ ast_summary(json_lexer.cj)")
            passed += 1
        else:
            print(f"  ✗ ast_summary(json_lexer.cj)")
            failed += 1
            errors.append("ast_summary(json_lexer.cj)")

        # ast_summary for json_parser.cj
        summary_parser = resp[3]
        sp_ok = summary_parser.get("ok") is True
        if sp_ok:
            print(f"  ✓ ast_summary(json_parser.cj)")
            passed += 1
        else:
            print(f"  ✗ ast_summary(json_parser.cj)")
            failed += 1
            errors.append("ast_summary(json_parser.cj)")

        # ast_parse of main.cj — should succeed
        parse_main = resp[4]
        pm_ok = parse_main.get("ok") is True
        pm_sexp = parse_main.get("data", {}).get("sexp", "")
        if pm_ok and "mainDefinition" in pm_sexp:
            print(f"  ✓ ast_parse(main.cj): contains mainDefinition")
            passed += 1
        else:
            print(f"  ✗ ast_parse(main.cj): ok={pm_ok}")
            failed += 1
            errors.append("ast_parse(main.cj)")

        # ast_query_nodes_with_text for functions in json_parser.cj
        query_funcs = resp[5]
        qf_ok = query_funcs.get("ok") is True
        qf_count = query_funcs.get("data", {}).get("matchCount", 0) if qf_ok else 0
        if qf_ok and qf_count > 0:
            print(f"  ✓ ast_query_nodes_with_text(functionDefinition): {qf_count} functions")
            passed += 1
        else:
            print(f"  ✗ ast_query_nodes_with_text: ok={qf_ok}, count={qf_count}")
            failed += 1
            errors.append("ast_query_nodes_with_text")

        # ══════════════════════════════════════════════════════════
        # Phase 4: Read back files and verify content
        # ══════════════════════════════════════════════════════════
        step("Phase 4: Read back key files and verify content")

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.read_file", {"path": "cjpm.toml"})             # 1
        c.call_tool("workspace.read_file", {"path": "src/json_value.cj"})     # 2
        c.call_tool("workspace.read_file", {"path": "src/json_parser.cj"})    # 3
        c.call_tool("workspace.search_text", {"query": "parseJson"})           # 4
        resp = c.execute()

        # cjpm.toml has correct content
        toml_content = resp[1].get("data", {}).get("content", "")
        if 'name = "jsonparser"' in toml_content:
            print(f"  ✓ cjpm.toml contains correct package name")
            passed += 1
        else:
            print(f"  ✗ cjpm.toml content mismatch")
            failed += 1
            errors.append("cjpm.toml content")

        # json_value.cj has JsonValue class
        jv_content = resp[2].get("data", {}).get("content", "")
        if "class JsonValue" in jv_content and "enum JsonValueKind" in jv_content:
            print(f"  ✓ json_value.cj has JsonValue class and JsonValueKind enum")
            passed += 1
        else:
            print(f"  ✗ json_value.cj missing expected types")
            failed += 1
            errors.append("json_value.cj content")

        # json_parser.cj has parseJson function
        jp_content = resp[3].get("data", {}).get("content", "")
        if "func parseJson" in jp_content and "class JsonParser" in jp_content:
            print(f"  ✓ json_parser.cj has JsonParser class and parseJson function")
            passed += 1
        else:
            print(f"  ✗ json_parser.cj missing expected content")
            failed += 1
            errors.append("json_parser.cj content")

        # search_text for parseJson across files
        search_result = resp[4]
        sr_ok = search_result.get("ok") is True
        sr_count = search_result.get("data", {}).get("count", 0)
        if sr_ok and sr_count >= 2:
            print(f"  ✓ search_text(parseJson): found in {sr_count} locations")
            passed += 1
        else:
            print(f"  ✗ search_text(parseJson): count={sr_count}")
            failed += 1
            errors.append("search_text(parseJson)")

        # ══════════════════════════════════════════════════════════
        # Phase 5: Build the project
        # ══════════════════════════════════════════════════════════
        step("Phase 5: Build the JsonParser project")

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.run_build")                                     # 1
        resp = c.execute()

        build_result = resp[1]
        build_ok = build_result.get("ok") is True
        build_summary = build_result.get("message", "")
        build_exit = build_result.get("data", {}).get("exitCode", -1)
        if build_ok and build_exit == 0:
            print(f"  ✓ workspace.run_build succeeded")
            passed += 1
        else:
            stderr = build_result.get("data", {}).get("stderr", "")
            stdout = build_result.get("data", {}).get("stdout", "")
            print(f"  ✗ workspace.run_build failed (exit={build_exit})")
            print(f"    stdout: {stdout[:500]}")
            print(f"    stderr: {stderr[:500]}")
            failed += 1
            errors.append("run_build")

        # ══════════════════════════════════════════════════════════
        # Phase 6: Run unit tests
        # ══════════════════════════════════════════════════════════
        step("Phase 6: Run unit tests for JsonParser")

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("workspace.run_test")                                      # 1
        resp = c.execute()

        test_result = resp[1]
        test_ok = test_result.get("ok") is True
        test_exit = test_result.get("data", {}).get("exitCode", -1)
        test_stdout = test_result.get("data", {}).get("stdout", "")
        if test_ok and test_exit == 0:
            print(f"  ✓ workspace.run_test succeeded")
            # Try to count passed tests from output
            if "Passed" in test_stdout:
                print(f"    {test_stdout.strip()}")
            passed += 1
        else:
            test_stderr = test_result.get("data", {}).get("stderr", "")
            print(f"  ✗ workspace.run_test failed (exit={test_exit})")
            print(f"    stdout: {test_stdout[:500]}")
            print(f"    stderr: {test_stderr[:500]}")
            failed += 1
            errors.append("run_test")

        # ══════════════════════════════════════════════════════════
        # Phase 7: Post-build verification — re-analyse and search
        # ══════════════════════════════════════════════════════════
        step("Phase 7: Post-build verification with AST analysis")

        c = client()
        c.start()
        c.call_tool("workspace.set_root", {"path": workspace})
        c.call_tool("cangjie.ast_summary", {"path": "src/json_parser_test.cj"})  # 1
        c.call_tool("cangjie.ast_query_nodes", {                                  # 2
            "path": "src/json_value.cj",
            "nodeType": "enumDefinition"
        })
        c.call_tool("workspace.list_files")                                       # 3
        resp = c.execute()

        # Test file AST summary — should detect test class
        test_summary = resp[1]
        ts_ok = test_summary.get("ok") is True
        ts_text = test_summary.get("data", {}).get("summary", "")
        if ts_ok and "class" in ts_text.lower():
            print(f"  ✓ ast_summary(test file) detected test class")
            passed += 1
        else:
            print(f"  ✗ ast_summary(test file)")
            failed += 1
            errors.append("ast_summary(test)")

        # Query enum definitions in json_value.cj
        enum_query = resp[2]
        eq_ok = enum_query.get("ok") is True
        eq_count = enum_query.get("data", {}).get("matchCount", 0)
        if eq_ok and eq_count >= 1:
            print(f"  ✓ ast_query_nodes(enumDefinition): found {eq_count}")
            passed += 1
        else:
            print(f"  ✗ ast_query_nodes(enumDefinition): count={eq_count}")
            failed += 1
            errors.append("ast_query_nodes(enum)")

        # list_files — should have cjpm.toml + src/ files
        files_resp = resp[3]
        fl_ok = files_resp.get("ok") is True
        fl_count = files_resp.get("data", {}).get("count", 0)
        if fl_ok and fl_count >= 6:
            print(f"  ✓ workspace.list_files: {fl_count} files")
            passed += 1
        else:
            print(f"  ✗ workspace.list_files: count={fl_count}")
            failed += 1
            errors.append("list_files(final)")

    except Exception as e:
        print(f"\n  ✗ FATAL ERROR: {e}")
        failed += 1
        errors.append(f"fatal: {e}")

    finally:
        if keep_workspace:
            print(f"\n  📁 Workspace preserved at: {workspace}")
        else:
            shutil.rmtree(workspace, ignore_errors=True)
            print(f"\n  🗑  Workspace cleaned up")

    return passed, failed, errors


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="E2E test: AI-driven JsonParser project via MCP tools"
    )
    parser.add_argument(
        "--bin", default=DEFAULT_BIN,
        help="Path to cangjiecoder binary"
    )
    parser.add_argument(
        "--keep", action="store_true",
        help="Keep the generated workspace after the test"
    )
    args = parser.parse_args()

    print("=" * 60)
    print("  E2E Test: JsonParser Project Development via MCP Tools")
    print("=" * 60)

    passed, failed, errors = run_e2e(args.bin, args.keep)

    print("\n" + "=" * 60)
    total = passed + failed
    print(f"  Results: {passed} passed, {failed} failed, {total} total")
    if errors:
        print(f"\n  Failures:")
        for e in errors:
            print(f"    • {e}")
    print("=" * 60)

    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
