package cangjiecoder.common

// UTF-8 continuation byte 形为 10xxxxxx
let UTF8_CONTINUATION_MASK: UInt8 = 0xC0
let UTF8_CONTINUATION_TAG: UInt8 = 0x80

/**
 * UTF-8 安全截断
 *
 * Cangjie 的 String 使用 UTF-8 编码，s[..n] 按字节索引
 * 若 n 落在多字节字符中间，会产生非法 UTF-8 序列
 */
public func truncateUtf8(s: String, maxBytes: Int64): String {
    if (s.size <= maxBytes) {
        return s
    }

    let bytes = s.toArray()
    var end = maxBytes
    while (end > 0 && (bytes[end] & UTF8_CONTINUATION_MASK) == UTF8_CONTINUATION_TAG) {
        end--
    }
    if (end <= 0) {
        return ""
    }
    return String.fromUtf8(bytes[..end])
}

/**
 * UTF-8 安全截断并追加后缀
 */
public func truncateWithEllipsis(s: String, maxBytes: Int64, suffix!: String = "..."): String {
    if (s.size <= maxBytes) {
        return s
    }
    return truncateUtf8(s, maxBytes) + suffix
}

/**
 * 头尾保留截断
 *
 * 适用于命令输出等需要同时看到首尾信息的场景
 */
public func truncateHeadTail(s: String, maxBytes: Int64): String {
    if (s.size <= maxBytes) {
        return s
    }

    let half = maxBytes / 2
    let head = truncateUtf8(s, half)
    let tailStart = s.size - half
    let bytes = s.toArray()
    var safeStart = tailStart
    while (safeStart < Int64(bytes.size) && (bytes[safeStart] & UTF8_CONTINUATION_MASK) == UTF8_CONTINUATION_TAG) {
        safeStart++
    }

    let tail = if (safeStart < Int64(bytes.size)) {
        String.fromUtf8(bytes[safeStart..])
    } else {
        ""
    }
    return "${head}\n... (省略 ${s.size - maxBytes} 字节) ...\n${tail}"
}
