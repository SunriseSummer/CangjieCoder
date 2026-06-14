package cangjiecoder.tools

import stdx.encoding.base64.*

/**
 * 文本解码兜底：优先按 UTF-8 解码，失败时在 Windows 上按 GBK(cp936) 解码
 *
 * 背景：Windows 子进程（python、git 等）写入管道或重定向文件的输出，
 * 默认使用系统代码页（简体中文 Windows 为 GBK/cp936）而非 UTF-8直接按
 * UTF-8 解码会失败，导致 run_bash 把正常文本当成 "<二进制输出>"、
 * read_file 抛 "Invalid utf8 byte sequence"
 *
 * 实现：纯仓颉实现的 GBK 解码器（不使用 C 互操作）Unicode 码点经
 * `Rune` 拼接为 UTF-8 字符串，GBK→Unicode 映射表由 `gbk_table.cj`
 * 内联存储（Base64 编码的小端 UInt16 数组），首次使用时惰性解码并缓存
 */

// GBK 编码参数：首字节 0x81..0xFE，尾字节 0x40..0x7E 与 0x80..0xFE
let GBK_LEAD_MIN: Byte = 0x81
let GBK_LEAD_MAX: Byte = 0xFE
let GBK_TRAIL_COUNT: Int64 = 190

// 惰性初始化的 GBK→Unicode 映射表（索引见 gbk_table.cj 注释）
var gbkTableCache: ?Array<UInt16> = None

/**
 * 解码并缓存 GBK 映射表，解析失败时返回空表（GBK 解码随之整体失败）
 */
func gbkTable(): Array<UInt16> {
    match (gbkTableCache) {
        case Some(t) => return t
        case None => ()
    }
    let table = match (fromBase64String(GBK_TABLE_B64)) {
        case Some(raw) =>
            let count = raw.size / 2
            Array<UInt16>(count, { i =>
                UInt16(raw[i * 2]) | (UInt16(raw[i * 2 + 1]) << 8)
            })
        case None => Array<UInt16>()
    }
    gbkTableCache = Some(table)
    return table
}

/**
 * 将 GBK 尾字节映射为表内列索引，非法尾字节返回 -1
 * 0x40..0x7E → 0..62，0x80..0xFE → 63..189
 */
func gbkTrailIndex(trail: Byte): Int64 {
    if (trail >= 0x40 && trail <= 0x7E) {
        return Int64(trail) - 0x40
    }
    if (trail >= 0x80 && trail <= 0xFE) {
        return 63 + (Int64(trail) - 0x80)
    }
    return -1
}

/**
 * 纯仓颉 GBK(cp936) 解码：
 *  - < 0x80 的字节按 ASCII 直通，
 *  - 0x81..0xFE 视为双字节首字节，与合法尾字节组合查表得到 Unicode 码点，
 *  - 任一字节不符合 GBK 结构（非法首/尾字节、悬挂首字节、未分配码位）
 *    则判定为非 GBK 文本，返回 None（调用方据此判定为二进制内容）
 */
func decodeGbk(bytes: Array<Byte>): ?String {
    let table = gbkTable()
    if (table.size == 0) {
        return None
    }
    let sb = StringBuilder()
    var i = 0
    let n = bytes.size
    while (i < n) {
        let b = bytes[i]
        if (b < 0x80) {
            sb.append(Rune(UInt32(b)))
            i++
            continue
        }
        if (b < GBK_LEAD_MIN || b > GBK_LEAD_MAX || i + 1 >= n) {
            return None
        }
        let trailIdx = gbkTrailIndex(bytes[i + 1])
        if (trailIdx < 0) {
            return None
        }
        let flat = (Int64(b) - Int64(GBK_LEAD_MIN)) * GBK_TRAIL_COUNT + trailIdx
        if (flat < 0 || flat >= table.size) {
            return None
        }
        let cp = table[flat]
        if (cp == 0) {
            return None
        }
        sb.append(Rune(UInt32(cp)))
        i += 2
    }
    return Some(sb.toString())
}

/** Windows 平台兜底解码：尝试 GBK */
@When[os == "Windows"]
func platformDecodeText(bytes: Array<Byte>): ?String {
    return decodeGbk(bytes)
}

/** 非 Windows 平台不做代码页兜底（默认 UTF-8） */
@When[os != "Windows"]
func platformDecodeText(_: Array<Byte>): ?String {
    return None
}

/**
 * 宽松文本解码：先按 UTF-8 解码，失败时在 Windows 上回退到 GBK
 * 仍失败则返回 None（调用方据此判定为真正的二进制内容）
 */
public func decodeTextLenient(bytes: Array<Byte>): ?String {
    match (tryDecodeUtf8(bytes)) {
        case Some(s) => return Some(s)
        case None => return platformDecodeText(bytes)
    }
}
