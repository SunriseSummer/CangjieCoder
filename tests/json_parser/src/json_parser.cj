// 简单 JSON 解析器示例
package json_parser

// JSON 值类型枚举
public enum JsonType <: ToString {
    | NULL | BOOL | NUMBER | STRING | ARRAY | OBJECT

    public func toString(): String {
        match (this) {
            case NULL => "NULL"
            case BOOL => "BOOL"
            case NUMBER => "NUMBER"
            case STRING => "STRING"
            case ARRAY => "ARRAY"
            case OBJECT => "OBJECT"
        }
    }
}

// JSON 解析器：将 JSON 字符串解析为结构化数据
public class JsonParser {
    var source: String = ""
    var pos: Int64 = 0

    public init() {}

    // 解析 JSON 字符串
    public func parse(input: String): JsonType {
        source = input.trimAscii()
        pos = 0
        if (source.isEmpty()) {
            return JsonType.NULL
        }
        return detectType()
    }

    // 检测当前位置的值类型
    func detectType(): JsonType {
        if (pos >= source.size) {
            return JsonType.NULL
        }
        let first = source[pos..pos + 1]
        match (first) {
            case "{" => return JsonType.OBJECT
            case "[" => return JsonType.ARRAY
            case "\"" => return JsonType.STRING
            case "t" | "f" => return JsonType.BOOL
            case "n" => return JsonType.NULL
            case _ => return JsonType.NUMBER
        }
    }

    // 获取当前解析位置
    public func currentPosition(): Int64 {
        return pos
    }
}

main() {
    let parser = JsonParser()
    let result = parser.parse("{\"key\": \"value\"}")
    println("Parsed type: ${result}")

    let arr = parser.parse("[1, 2, 3]")
    println("Array type: ${arr}")
}
