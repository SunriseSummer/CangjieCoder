package json_parser

import std.collection.*
import std.convert.*

open class JsonNode {
    public open func render(): String {
        ""
    }
}

class JsonNullNode <: JsonNode {
    public override func render(): String {
        "null"
    }
}

class JsonBoolNode <: JsonNode {
    let value: Bool

    public init(value: Bool) {
        this.value = value
    }

    public override func render(): String {
        if (value) {
            return "true"
        }
        return "false"
    }
}

class JsonNumberNode <: JsonNode {
    let value: Float64

    public init(value: Float64) {
        this.value = value
    }

    public override func render(): String {
        return value.toString()
    }
}

class JsonStringNode <: JsonNode {
    let value: String

    public init(value: String) {
        this.value = value
    }

    public override func render(): String {
        return "\"${escapeJsonString(value)}\""
    }
}

class JsonArrayNode <: JsonNode {
    let items: ArrayList<JsonNode>

    public init(items: ArrayList<JsonNode>) {
        this.items = items
    }

    public override func render(): String {
        let renderedItems = ArrayList<String>()
        for (item in items) {
            renderedItems.add(item.render())
        }
        return "[${String.join(renderedItems.toArray(), delimiter: ",")}]"
    }
}

class JsonObjectNode <: JsonNode {
    let entries: ArrayList<(String, JsonNode)>

    public init(entries: ArrayList<(String, JsonNode)>) {
        this.entries = entries
    }

    public override func render(): String {
        let renderedEntries = ArrayList<String>()
        for ((key, value) in entries) {
            renderedEntries.add("\"${escapeJsonString(key)}\":${value.render()}")
        }
        return "{${String.join(renderedEntries.toArray(), delimiter: ",")}}"
    }
}

class JsonParseException <: Exception {
    public init(message: String) {
        super(message)
    }
}

class JsonParser {
    let bytes: Array<Byte>
    var index: Int64 = 0

    public init(text: String) {
        bytes = text.toArray()
    }

    public func parse(): JsonNode {
        skipWhitespace()
        let result = parseValue()
        skipWhitespace()
        if (index != bytes.size) {
            fail("Unexpected trailing content")
        }
        return result
    }

    func parseValue(): JsonNode {
        skipWhitespace()
        let current = currentByte()
        match (current) {
            case b'{' => return parseObject()
            case b'[' => return parseArray()
            case b'"' => return JsonStringNode(parseString())
            case b't' => return parseTrue()
            case b'f' => return parseFalse()
            case b'n' => return parseNull()
            case b'-' => return parseNumber()
            case _ =>
                if (isDigit(current)) {
                    return parseNumber()
                }
                fail("Unexpected token '${displayByte(current)}' while parsing value")
        }
    }

    func parseObject(): JsonNode {
        expect(b'{')
        skipWhitespace()
        let entries = ArrayList<(String, JsonNode)>()
        if (currentByte() == b'}') {
            advance()
            return JsonObjectNode(entries)
        }

        while (index < bytes.size) {
            skipWhitespace()
            let key = parseString()
            skipWhitespace()
            expect(b':')
            skipWhitespace()
            entries.add((key, parseValue()))
            skipWhitespace()
            let next = currentByte()
            if (next == b'}') {
                advance()
                return JsonObjectNode(entries)
            }
            expect(b',')
        }
        fail("Unterminated object")
    }

    func parseArray(): JsonNode {
        expect(b'[')
        skipWhitespace()
        let items = ArrayList<JsonNode>()
        if (currentByte() == b']') {
            advance()
            return JsonArrayNode(items)
        }

        while (index < bytes.size) {
            items.add(parseValue())
            skipWhitespace()
            let next = currentByte()
            if (next == b']') {
                advance()
                return JsonArrayNode(items)
            }
            expect(b',')
            skipWhitespace()
        }
        fail("Unterminated array")
    }

    func parseString(): String {
        expect(b'"')
        let buffer = ArrayList<Byte>()
        while (index < bytes.size) {
            let current = currentByte()
            advance()
            if (current == b'"') {
                return String.fromUtf8(buffer.toArray())
            }
            if (current == b'\\') {
                if (index >= bytes.size) {
                    fail("Unterminated escape sequence")
                }
                let escaped = currentByte()
                advance()
                match (escaped) {
                    case b'"' => buffer.add(b'"')
                    case b'\\' => buffer.add(b'\\')
                    case b'/' => buffer.add(b'/')
                    case b'b' => buffer.add(b'\b')
                    case b'f' => buffer.add(b'\f')
                    case b'n' => buffer.add(b'\n')
                    case b'r' => buffer.add(b'\r')
                    case b't' => buffer.add(b'\t')
                    case _ => fail("Unsupported escape sequence")
                }
                continue
            }
            buffer.add(current)
        }
        fail("Unterminated string literal")
    }

    func parseTrue(): JsonNode {
        expectKeyword("true")
        return JsonBoolNode(true)
    }

    func parseFalse(): JsonNode {
        expectKeyword("false")
        return JsonBoolNode(false)
    }

    func parseNull(): JsonNode {
        expectKeyword("null")
        return JsonNullNode()
    }

    func parseNumber(): JsonNode {
        let start = index
        if (currentByte() == b'-') {
            advance()
        }
        consumeDigits(required: true)
        if (index < bytes.size && currentByte() == b'.') {
            advance()
            consumeDigits(required: true)
        }
        if (index < bytes.size) {
            let current = currentByte()
            if (current == b'e' || current == b'E') {
                advance()
                if (index < bytes.size) {
                    let sign = currentByte()
                    if (sign == b'+' || sign == b'-') {
                        advance()
                    }
                }
                consumeDigits(required: true)
            }
        }
        let numberBytes = Array<Byte>(index - start, { idx => bytes[start + idx] })
        let numberText = String.fromUtf8(numberBytes)
        return JsonNumberNode(Float64.parse(numberText))
    }

    func consumeDigits(required!: Bool = true): Unit {
        if (index >= bytes.size) {
            if (required) {
                fail("Expected digit but reached end of input")
            }
            return
        }
        if (!isDigit(currentByte())) {
            if (!required) {
                return
            }
            fail("Expected digit")
        }
        while (index < bytes.size && isDigit(currentByte())) {
            advance()
        }
    }

    func expectKeyword(keyword: String): Unit {
        for (byte in keyword.toArray()) {
            expect(byte)
        }
    }

    func expect(expected: Byte): Unit {
        let found = currentByte()
        if (found != expected) {
            fail("Expected '${displayByte(expected)}' but found '${displayByte(found)}'")
        }
        advance()
    }

    func skipWhitespace(): Unit {
        while (index < bytes.size) {
            let current = currentByte()
            if (current == b' ' || current == b'\n' || current == b'\r' || current == b'\t') {
                advance()
                continue
            }
            break
        }
    }

    func currentByte(): Byte {
        if (index >= bytes.size) {
            fail("Unexpected end of input")
        }
        return bytes[index]
    }

    func advance(): Unit {
        index += 1
    }

    func isDigit(value: Byte): Bool {
        return value >= b'0' && value <= b'9'
    }

    func fail(message: String): Nothing {
        throw JsonParseException("${message} at byte ${index}")
    }
}

func parseJson(text: String): JsonNode {
    return JsonParser(text).parse()
}

func escapeJsonString(text: String): String {
    let buffer = ArrayList<String>()
    for (byte in text.toArray()) {
        match (byte) {
            case b'"' => buffer.add("\\\"")
            case b'\\' => buffer.add("\\\\")
            case b'\n' => buffer.add("\\n")
            case b'\r' => buffer.add("\\r")
            case b'\t' => buffer.add("\\t")
            case _ => buffer.add(String.fromUtf8([byte]))
        }
    }
    return String.join(buffer.toArray())
}

func displayByte(value: Byte): String {
    if (value == b'\n') {
        return "\\n"
    }
    if (value == b'\r') {
        return "\\r"
    }
    if (value == b'\t') {
        return "\\t"
    }
    if (value == b'\"') {
        return "\\\""
    }
    if (value == b'\\') {
        return "\\\\"
    }
    return String.fromUtf8([value])
}
