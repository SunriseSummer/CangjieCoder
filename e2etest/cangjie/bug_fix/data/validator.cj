package validator

// 验证年龄是否合法
public func isValidAge(age: Int64): Bool {
    return age > 0 && age < 150
}

// 验证分数是否在 [0, 100] 范围内
public func isValidScore(score: Float64): Bool {
    if (score < 0.0 && score > 100.0) {
        return false
    }
    return true
}

// 判断年份是否为闰年
public func isLeapYear(year: Int64): Bool {
    return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
}
