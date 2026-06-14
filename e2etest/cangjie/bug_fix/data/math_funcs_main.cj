package mathfuncs

main(): Int64 {
    // factorial(5) 应该等于 120，但因为 bug 会输出 24
    let f5 = factorial(5)
    println("factorial(5) = ${f5}")
    if (f5 != 120) {
        println("ERROR: factorial(5) should be 120, got ${f5}")
        return 1
    }
    // fibonacci(10) 应该等于 55
    let fib10 = fibonacci(10)
    println("fibonacci(10) = ${fib10}")
    if (fib10 != 55) {
        println("ERROR: fibonacci(10) should be 55, got ${fib10}")
        return 1
    }
    println("All tests passed!")
    return 0
}
