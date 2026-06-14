package cangjiecoder.tools

import std.regex.*

/**
 * 简易 glob → 正则转换：
 *  - `**`       匹配跨目录的任意字符（包含 `/`）
 *  - `*`        匹配同一段内任意字符（不含 `/`）
 *  - `?`        匹配同一段内的单字符
 *  - 其它       原样转义
 *
 * 该实现完全用于路径匹配，不处理字符类 `[...]`
 */

// glob 通配符的字节值
let BYTE_ASTERISK: UInt8 = 42     // '*'
let BYTE_QUESTION: UInt8 = 63     // '?'
let BYTE_SLASH: UInt8 = 47        // '/'

// 正则特殊字符的字节值
let BYTE_DOT: UInt8 = 46          // '.'
let BYTE_PLUS: UInt8 = 43         // '+'
let BYTE_LPAREN: UInt8 = 40       // '('
let BYTE_RPAREN: UInt8 = 41       // ')'
let BYTE_LBRACE: UInt8 = 123      // '{'
let BYTE_RBRACE: UInt8 = 125      // '}'
let BYTE_LBRACKET: UInt8 = 91     // '['
let BYTE_RBRACKET: UInt8 = 93     // ']'
let BYTE_CARET: UInt8 = 94        // '^'
let BYTE_DOLLAR: UInt8 = 36       // '$'
let BYTE_PIPE: UInt8 = 124        // '|'
let BYTE_BACKSLASH: UInt8 = 92    // '\'

public func globMatch(pattern: String, path: String): Bool {
    let regex = globToRegex(pattern)
    let re = Regex(regex)
    return re.matches(path)
}

public func globToRegex(pattern: String): String {
    let sb = StringBuilder()
    sb.append("^")
    var i: Int64 = 0
    let patLen = pattern.size
    let bytes = pattern.toArray()
    while (i < patLen) {
        let ch = bytes[i]
        if (ch == BYTE_ASTERISK) {
            if (i + 1 < patLen && bytes[i + 1] == BYTE_ASTERISK) {
                sb.append(".*")
                i += 2
                // 跳过可能紧跟的 '/'
                if (i < patLen && bytes[i] == BYTE_SLASH) {
                    i += 1
                }
            } else {
                sb.append("[^/]*")
                i += 1
            }
        } else if (ch == BYTE_QUESTION) {
            sb.append("[^/]")
            i += 1
        } else if (isRegexSpecial(ch)) {
            sb.append("\\")
            sb.append(Rune(ch).toString())
            i += 1
        } else {
            sb.append(Rune(ch).toString())
            i += 1
        }
    }
    sb.append("$")
    return sb.toString()
}

func isRegexSpecial(ch: UInt8): Bool {
    return ch == BYTE_DOT || ch == BYTE_PLUS || ch == BYTE_LPAREN || ch == BYTE_RPAREN ||
           ch == BYTE_LBRACE || ch == BYTE_RBRACE || ch == BYTE_LBRACKET || ch == BYTE_RBRACKET ||
           ch == BYTE_CARET || ch == BYTE_DOLLAR || ch == BYTE_PIPE || ch == BYTE_BACKSLASH
}
