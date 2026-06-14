package myproject

// 数学工具函数
public func myAbs(n: Int64): Int64 {
    if (n < 0) { return -n }
    return n
}

public func myMax(a: Int64, b: Int64): Int64 {
    if (a > b) { return a }
    return b
}

public func myMin(a: Int64, b: Int64): Int64 {
    if (a < b) { return a }
    return b
}
