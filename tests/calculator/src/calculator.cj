// 表达式计算器
// 演示：递归 enum、递归下降解析、模式匹配、运算符优先级、异常处理
package calculator

import std.collection.*
import std.convert.*

// 表达式 AST 节点
public enum Expr <: ToString {
    | Num(Float64)
    | Add(Expr, Expr)
    | Sub(Expr, Expr)
    | Mul(Expr, Expr)
    | Div(Expr, Expr)

    public func toString(): String {
        match (this) {
            case Num(n) =>
                if (n == Float64(Int64(n))) {
                    "${Int64(n)}"
                } else {
                    "${n}"
                }
            case Add(l, r) => "(${l} + ${r})"
            case Sub(l, r) => "(${l} - ${r})"
            case Mul(l, r) => "(${l} * ${r})"
            case Div(l, r) => "(${l} / ${r})"
        }
    }
}

// 计算异常
public class CalcException <: Exception {
    let msg: String
    public init(message: String) {
        this.msg = message
    }
    public func toString(): String { msg }
}

// 对表达式 AST 求值
public func evaluate(expr: Expr): Float64 {
    match (expr) {
        case Num(n) => n
        case Add(l, r) => evaluate(l) + evaluate(r)
        case Sub(l, r) => evaluate(l) - evaluate(r)
        case Mul(l, r) => evaluate(l) * evaluate(r)
        case Div(l, r) =>
            let divisor = evaluate(r)
            if (divisor == 0.0) {
                throw CalcException("Division by zero")
            }
            evaluate(l) / divisor
    }
}

// Token 类型
enum TokenKind {
    | TNumber | TPlus | TMinus | TStar | TSlash | TLParen | TRParen | TEof
}

// Token 结构
struct Token {
    Token(let kind: TokenKind, let value: String) {}
}

// 词法分析器
class Lexer {
    var source: String = ""
    var pos: Int64 = 0
    var tokens: ArrayList<Token> = ArrayList<Token>()
    var tokenPos: Int64 = 0

    init(input: String) {
        source = input
        pos = 0
        tokenize()
        tokenPos = 0
    }

    func tokenize(): Unit {
        while (pos < source.size) {
            let ch = source[pos..pos + 1]
            match (ch) {
                case " " | "\t" | "\n" | "\r" =>
                    pos += 1
                case "+" =>
                    tokens.add(Token(TokenKind.TPlus, "+"))
                    pos += 1
                case "-" =>
                    tokens.add(Token(TokenKind.TMinus, "-"))
                    pos += 1
                case "*" =>
                    tokens.add(Token(TokenKind.TStar, "*"))
                    pos += 1
                case "/" =>
                    tokens.add(Token(TokenKind.TSlash, "/"))
                    pos += 1
                case "(" =>
                    tokens.add(Token(TokenKind.TLParen, "("))
                    pos += 1
                case ")" =>
                    tokens.add(Token(TokenKind.TRParen, ")"))
                    pos += 1
                case _ =>
                    if (isDigitChar(ch) || ch == ".") {
                        let start = pos
                        while (pos < source.size && (isDigitChar(source[pos..pos + 1]) || source[pos..pos + 1] == ".")) {
                            pos += 1
                        }
                        tokens.add(Token(TokenKind.TNumber, source[start..pos]))
                    } else {
                        throw CalcException("Unexpected character: '${ch}' at position ${pos}")
                    }
            }
        }
        tokens.add(Token(TokenKind.TEof, ""))
    }

    func peek(): Token {
        return tokens[tokenPos]
    }

    func next(): Token {
        let tok = tokens[tokenPos]
        if (tokenPos < tokens.size - 1) {
            tokenPos += 1
        }
        return tok
    }
}

// 判断单字符是否为数字
func isDigitChar(ch: String): Bool {
    return ch == "0" || ch == "1" || ch == "2" || ch == "3" || ch == "4" ||
           ch == "5" || ch == "6" || ch == "7" || ch == "8" || ch == "9"
}

// 递归下降表达式解析器
// 语法：
//   expr    = term (('+' | '-') term)*
//   term    = factor (('*' | '/') factor)*
//   factor  = NUMBER | '(' expr ')' | '-' factor
public class ExprParser {
    var lexer: Lexer = Lexer("")

    public init() {}

    // 解析表达式字符串为 AST
    public func parse(input: String): Expr {
        lexer = Lexer(input)
        let result = parseExpr()
        let tok = lexer.peek()
        match (tok.kind) {
            case TEof => ()
            case _ => throw CalcException("Unexpected token: '${tok.value}'")
        }
        return result
    }

    // 解析加减法表达式
    func parseExpr(): Expr {
        var left = parseTerm()
        while (true) {
            let tok = lexer.peek()
            match (tok.kind) {
                case TPlus =>
                    lexer.next()
                    left = Expr.Add(left, parseTerm())
                case TMinus =>
                    lexer.next()
                    left = Expr.Sub(left, parseTerm())
                case _ => break
            }
        }
        return left
    }

    // 解析乘除法表达式
    func parseTerm(): Expr {
        var left = parseFactor()
        while (true) {
            let tok = lexer.peek()
            match (tok.kind) {
                case TStar =>
                    lexer.next()
                    left = Expr.Mul(left, parseFactor())
                case TSlash =>
                    lexer.next()
                    left = Expr.Div(left, parseFactor())
                case _ => break
            }
        }
        return left
    }

    // 解析因子（数字、括号、一元负号）
    func parseFactor(): Expr {
        let tok = lexer.peek()
        match (tok.kind) {
            case TNumber =>
                lexer.next()
                return Expr.Num(Float64.parse(tok.value))
            case TLParen =>
                lexer.next()
                let inner = parseExpr()
                let closing = lexer.next()
                match (closing.kind) {
                    case TRParen => ()
                    case _ => throw CalcException("Expected ')' but got '${closing.value}'")
                }
                return inner
            case TMinus =>
                lexer.next()
                let operand = parseFactor()
                return Expr.Sub(Expr.Num(0.0), operand)
            case _ =>
                throw CalcException("Unexpected token: '${tok.value}'")
        }
    }
}

// 便捷求值函数
public func calc(expression: String): Float64 {
    let parser = ExprParser()
    let ast = parser.parse(expression)
    return evaluate(ast)
}

main() {
    let parser = ExprParser()

    // 基本运算
    let expressions = [
        "2 + 3",
        "10 - 4",
        "3 * 7",
        "20 / 4",
        "2 + 3 * 4",
        "(2 + 3) * 4",
        "100 / (2 + 3)",
        "-5 + 3",
        "1.5 * 2 + 0.5"
    ]

    for (expression in expressions) {
        let ast = parser.parse(expression)
        let result = evaluate(ast)
        let resultStr = if (result == Float64(Int64(result))) {
            "${Int64(result)}"
        } else {
            "${result}"
        }
        println("${expression} = ${resultStr}  (AST: ${ast})")
    }
}
