package calculator

import std.math.*

// 基础四则运算
public func add(a: Float64, b: Float64): Float64 {
    return a + b
}

public func sub(a: Float64, b: Float64): Float64 {
    return a - b
}

public func mul(a: Float64, b: Float64): Float64 {
    return a * b
}

public func div(a: Float64, b: Float64): Float64 {
    if (b == 0.0) {
        throw ArithmeticException("division by zero")
    }
    return a / b
}
