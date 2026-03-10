package testproject

public func add(a: Int64, b: Int64): Int64 {
    return a + b
}

public func multiply(a: Int64, b: Int64): Int64 {
    return a * b
}

public func isEven(n: Int64): Bool {
    return n % 2 == 0
}

public class Calculator {
    var result: Int64 = 0

    public func addValue(value: Int64): Unit {
        result += value
    }

    public func reset(): Unit {
        result = 0
    }

    public func getResult(): Int64 {
        return result
    }
}
