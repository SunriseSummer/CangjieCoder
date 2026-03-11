// 完整的递归下降 JSON 解析器
// 演示：enum（递归）、class、ArrayList、HashMap、模式匹配、字符串处理、异常处理
package json_parser

import std.collection.*
import std.convert.*

// JSON 值类型枚举（递归数据结构）
public enum JsonValue <: ToString {
    | JNull
    | JBool(Bool)
    | JNumber(Float64)
    | JString(String)
    | JArray(ArrayList<JsonValue>)
    | JObject(ArrayList<(String, JsonValue)>)

    public func toString(): String {
        match (this) {
            case JNull => "null"
            case JBool(b) => if (b) { "true" } else { "false" }
            case JNumber(n) =>
                if (n == Float64(Int64(n))) {
                    "${Int64(n)}"
                } else {
                    "${n}"
                }
            case JString(s) => "\"${escapeJsonString(s)}\""
            case JArray(items) =>
                let parts = ArrayList<String>()
                for (item in items) {
                    parts.add(item.toString())
                }
                "[${String.join(parts.toArray(), delimiter: ",")}]"
            case JObject(entries) =>
                let parts = ArrayList<String>()
                for ((key, value) in entries) {
                    parts.add("\"${escapeJsonString(key)}\":${value.toString()}")
                }
                "{${String.join(parts.toArray(), delimiter: ",")}}"
        }
    }

    // 类型判断辅助方法
    public prop isNull: Bool {
        get() {
            match (this) { case JNull => true; case _ => false }
        }
    }
    public prop isBool: Bool {
        get() {
            match (this) { case JBool(_) => true; case _ => false }
        }
    }
    public prop isNumber: Bool {
        get() {
            match (this) { case JNumber(_) => true; case _ => false }
        }
    }
    public prop isString: Bool {
        get() {
            match (this) { case JString(_) => true; case _ => false }
        }
    }
    public prop isArray: Bool {
        get() {
            match (this) { case JArray(_) => true; case _ => false }
        }
    }
    public prop isObject: Bool {
        get() {
            match (this) { case JObject(_) => true; case _ => false }
        }
    }

    // 取值辅助方法
    public func asBool(): Bool {
        match (this) {
            case JBool(b) => b
            case _ => throw IllegalArgumentException("Not a Bool")
        }
    }

    public func asNumber(): Float64 {
        match (this) {
            case JNumber(n) => n
            case _ => throw IllegalArgumentException("Not a Number")
        }
    }

    public func asStr(): String {
        match (this) {
            case JString(s) => s
            case _ => throw IllegalArgumentException("Not a String")
        }
    }

    public func asArray(): ArrayList<JsonValue> {
        match (this) {
            case JArray(items) => items
            case _ => throw IllegalArgumentException("Not an Array")
        }
    }

    // 按 key 获取 Object 字段
    public func get(key: String): ?JsonValue {
        match (this) {
            case JObject(entries) =>
                for ((k, v) in entries) {
                    if (k == key) {
                        return v
                    }
                }
                return None
            case _ => None
        }
    }
}

// JSON 字符串转义
func escapeJsonString(s: String): String {
    return s.replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
}

// JSON 解析异常
public class JsonParseException <: Exception {
    let msg: String
    public init(message: String) {
        this.msg = message
    }
    public func toString(): String { msg }
}

// 递归下降 JSON 解析器
public class JsonParser {
    var source: String = ""
    var pos: Int64 = 0

    public init() {}

    // 解析 JSON 字符串，返回解析后的 JsonValue
    public func parse(input: String): JsonValue {
        source = input
        pos = 0
        skipWhitespace()
        if (pos >= source.size) {
            return JsonValue.JNull
        }
        let result = parseValue()
        skipWhitespace()
        return result
    }

    // 解析一个 JSON 值
    func parseValue(): JsonValue {
        skipWhitespace()
        if (pos >= source.size) {
            throw JsonParseException("Unexpected end of input at position ${pos}")
        }
        let ch = source[pos..pos + 1]
        match (ch) {
            case "\"" => return parseString()
            case "{" => return parseObject()
            case "[" => return parseArray()
            case "t" | "f" => return parseBool()
            case "n" => return parseNull()
            case _ => return parseNumber()
        }
    }

    // 解析字符串
    func parseString(): JsonValue {
        expect("\"")
        let result = ArrayList<String>()
        while (pos < source.size) {
            let ch = source[pos..pos + 1]
            if (ch == "\"") {
                pos += 1
                return JsonValue.JString(String.join(result.toArray(), delimiter: ""))
            }
            if (ch == "\\") {
                pos += 1
                if (pos >= source.size) {
                    throw JsonParseException("Unexpected end of escape sequence")
                }
                let escaped = source[pos..pos + 1]
                match (escaped) {
                    case "\"" => result.add("\"")
                    case "\\" => result.add("\\")
                    case "/" => result.add("/")
                    case "n" => result.add("\n")
                    case "r" => result.add("\r")
                    case "t" => result.add("\t")
                    case _ => result.add(escaped)
                }
                pos += 1
            } else {
                result.add(ch)
                pos += 1
            }
        }
        throw JsonParseException("Unterminated string")
    }

    // 解析对象
    func parseObject(): JsonValue {
        expect("{")
        skipWhitespace()
        let entries = ArrayList<(String, JsonValue)>()
        if (pos < source.size && source[pos..pos + 1] == "}") {
            pos += 1
            return JsonValue.JObject(entries)
        }
        while (pos < source.size) {
            skipWhitespace()
            let keyValue = parseString()
            let key = match (keyValue) {
                case JString(s) => s
                case _ => throw JsonParseException("Object key must be a string")
            }
            skipWhitespace()
            expect(":")
            skipWhitespace()
            let value = parseValue()
            entries.add((key, value))
            skipWhitespace()
            if (pos < source.size && source[pos..pos + 1] == ",") {
                pos += 1
                continue
            }
            break
        }
        skipWhitespace()
        expect("}")
        return JsonValue.JObject(entries)
    }

    // 解析数组
    func parseArray(): JsonValue {
        expect("[")
        skipWhitespace()
        let items = ArrayList<JsonValue>()
        if (pos < source.size && source[pos..pos + 1] == "]") {
            pos += 1
            return JsonValue.JArray(items)
        }
        while (pos < source.size) {
            skipWhitespace()
            items.add(parseValue())
            skipWhitespace()
            if (pos < source.size && source[pos..pos + 1] == ",") {
                pos += 1
                continue
            }
            break
        }
        skipWhitespace()
        expect("]")
        return JsonValue.JArray(items)
    }

    // 解析布尔值
    func parseBool(): JsonValue {
        if (startsWith("true")) {
            pos += 4
            return JsonValue.JBool(true)
        }
        if (startsWith("false")) {
            pos += 5
            return JsonValue.JBool(false)
        }
        throw JsonParseException("Invalid boolean at position ${pos}")
    }

    // 解析 null
    func parseNull(): JsonValue {
        if (startsWith("null")) {
            pos += 4
            return JsonValue.JNull
        }
        throw JsonParseException("Invalid null at position ${pos}")
    }

    // 解析数字（整数和浮点数）
    func parseNumber(): JsonValue {
        let start = pos
        if (pos < source.size && source[pos..pos + 1] == "-") {
            pos += 1
        }
        while (pos < source.size && isDigit(source[pos..pos + 1])) {
            pos += 1
        }
        if (pos < source.size && source[pos..pos + 1] == ".") {
            pos += 1
            while (pos < source.size && isDigit(source[pos..pos + 1])) {
                pos += 1
            }
        }
        // 支持科学计数法
        if (pos < source.size && (source[pos..pos + 1] == "e" || source[pos..pos + 1] == "E")) {
            pos += 1
            if (pos < source.size && (source[pos..pos + 1] == "+" || source[pos..pos + 1] == "-")) {
                pos += 1
            }
            while (pos < source.size && isDigit(source[pos..pos + 1])) {
                pos += 1
            }
        }
        if (pos == start) {
            throw JsonParseException("Invalid number at position ${pos}")
        }
        let numStr = source[start..pos]
        return JsonValue.JNumber(Float64.parse(numStr))
    }

    // 跳过空白字符
    func skipWhitespace(): Unit {
        while (pos < source.size) {
            let ch = source[pos..pos + 1]
            if (ch == " " || ch == "\t" || ch == "\n" || ch == "\r") {
                pos += 1
            } else {
                break
            }
        }
    }

    // 期望消费指定字符
    func expect(expected: String): Unit {
        if (pos >= source.size || source[pos..pos + expected.size] != expected) {
            let actual = if (pos < source.size) { source[pos..pos + 1] } else { "EOF" }
            throw JsonParseException("Expected '${expected}' but got '${actual}' at position ${pos}")
        }
        pos += expected.size
    }

    // 检查当前位置是否以指定文本开头
    func startsWith(text: String): Bool {
        if (pos + text.size > source.size) {
            return false
        }
        return source[pos..pos + text.size] == text
    }

    // 获取当前解析位置
    public func currentPosition(): Int64 {
        return pos
    }
}

// 判断单字符串是否为数字
func isDigit(ch: String): Bool {
    return ch == "0" || ch == "1" || ch == "2" || ch == "3" || ch == "4" ||
           ch == "5" || ch == "6" || ch == "7" || ch == "8" || ch == "9"
}

main() {
    let parser = JsonParser()

    // 基本类型解析
    println("null => ${parser.parse("null")}")
    println("true => ${parser.parse("true")}")
    println("42 => ${parser.parse("42")}")
    println("3.14 => ${parser.parse("3.14")}")

    // 字符串解析
    let strResult = parser.parse("\"hello world\"")
    println("string => ${strResult}")

    // 数组解析
    let arrResult = parser.parse("[1, 2, 3]")
    println("array => ${arrResult}")

    // 对象解析
    let objResult = parser.parse("{\"name\": \"CangjieCoder\", \"version\": 1, \"features\": [\"ast\", \"lsp\"]}")
    println("object => ${objResult}")

    // 嵌套结构
    let nested = parser.parse("{\"data\": {\"items\": [1, null, true]}}")
    println("nested => ${nested}")

    // 字段访问
    if (let Some(name) <- objResult.get("name")) {
        println("name field => ${name.asStr()}")
    }
}
