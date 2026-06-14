package validator

main(): Int64 {
    // isValidAge(0) 应该返回 true（0 是合法年龄）
    if (!isValidAge(0)) {
        println("ERROR: age 0 should be valid")
        return 1
    }
    // isValidAge(150) 应该返回 true
    if (!isValidAge(150)) {
        println("ERROR: age 150 should be valid")
        return 1
    }
    // isValidScore(-1) 应该返回 false
    if (isValidScore(-1.0)) {
        println("ERROR: score -1 should be invalid")
        return 1
    }
    // isValidScore(101) 应该返回 false
    if (isValidScore(101.0)) {
        println("ERROR: score 101 should be invalid")
        return 1
    }
    println("All validation tests passed!")
    return 0
}
