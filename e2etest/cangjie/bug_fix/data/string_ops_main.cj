package stringops

main(): Int64 {
    // countUpperCase("Hello World") 应该返回 2（H 和 W）
    let upper = countUpperCase("Hello World")
    if (upper != 2) {
        println("ERROR: countUpperCase should be 2, got ${upper}")
        return 1
    }
    // maskDigits("abc0123") 应该返回 "abc****"
    let masked = maskDigits("abc0123")
    if (masked != "abc****") {
        println("ERROR: maskDigits should be 'abc****', got '${masked}'")
        return 1
    }
    println("All string ops tests passed!")
    return 0
}
