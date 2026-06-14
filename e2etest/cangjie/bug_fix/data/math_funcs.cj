package mathfuncs

// 计算 n 的阶乘
public func factorial(n: Int64): Int64 {
    if (n < 0) {
        throw IllegalArgumentException("n must be non-negative")
    }
    if (n == 0) {
        return 1
    }
    var result: Int64 = 1
    for (i in 1..n) {
        result = result * i
    }
    return result
}

// 计算斐波那契数列第 n 项
public func fibonacci(n: Int64): Int64 {
    if (n <= 0) { return 0 }
    if (n == 1) { return 1 }
    var a: Int64 = 0
    var b: Int64 = 1
    for (i in 2..=n) {
        let temp = a + b
        a = b
        b = temp
    }
    return b
}
