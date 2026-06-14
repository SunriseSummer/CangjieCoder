package cangjiecoder.httpx

import std.collection.*
import std.io.*

let READ_BUFFER_SIZE: Int64 = 8192

/**
 * 从 InputStream 读取全部字节后统一解码
 *
 * chunked 传输可能把 UTF-8 多字节字符拆到相邻块边界
 * 先收集完整字节再解码可以避免逐块解码导致的 Invalid utf8 byte sequence
 */
func readBodyAsString(stream: InputStream): String {
    let buf = Array<Byte>(READ_BUFFER_SIZE, {_ => 0})
    let chunks = ArrayList<Array<Byte>>()
    var totalLen: Int64 = 0
    while (true) {
        let bytesRead = stream.read(buf)
        if (bytesRead <= 0) {
            break
        }
        let chunk = Array<Byte>(bytesRead, {i => buf[i]})
        chunks.add(chunk)
        totalLen += bytesRead
    }
    if (totalLen == 0) {
        return ""
    }
    let all = Array<Byte>(totalLen, {_ => 0})
    var offset: Int64 = 0
    for (chunk in chunks) {
        for (byte in chunk) {
            all[offset] = byte
            offset++
        }
    }
    return String.fromUtf8(all)
}
