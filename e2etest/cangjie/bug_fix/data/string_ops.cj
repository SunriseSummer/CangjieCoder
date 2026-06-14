package stringops

// 统计字符串中大写字母的数量
public func countUpperCase(s: String): Int64 {
    var count: Int64 = 0
    for (c in s) {
        if (c >= r'a' && c <= r'z') {
            count = count + 1
        }
    }
    return count
}

// 将字符串中的数字字符替换为 *
public func maskDigits(s: String): String {
    let sb = StringBuilder()
    for (c in s) {
        if (c >= r'1' && c <= r'9') {
            sb.append(r'*')
        } else {
            sb.append(c)
        }
    }
    return sb.toString()
}
