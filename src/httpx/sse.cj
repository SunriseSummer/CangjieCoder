package cangjiecoder.httpx

import std.collection.*
import stdx.net.http.*

let SSE_DATA_PREFIX_LEN: Int64 = 5

/**
 * 字节级读取 SSE 流
 *
 * 按字节分行后再解码 UTF-8
 * 避免 StringReader 在 chunk 边界拆开 CJK 等多字节字符
 */
func readStream(resp: HttpResponse, onChunk: ?StreamCallback): String {
    let stream = resp.body
    let buf = Array<Byte>(READ_BUFFER_SIZE, {_ => 0})
    let sb = StringBuilder()
    var pending = StringBuilder()
    var lineBytes = ArrayList<Byte>()

    while (true) {
        let bytesRead = stream.read(buf)
        if (bytesRead <= 0) {
            break
        }
        for (i in 0..bytesRead) {
            let b = buf[i]
            if (b == 0x0A) {
                let line = decodeLine(lineBytes)
                lineBytes = ArrayList<Byte>()
                if (line.isEmpty()) {
                    if (pending.size != 0) {
                        let done = processSseEvent(pending.toString(), sb, onChunk)
                        pending = StringBuilder()
                        if (done) {
                            return sb.toString()
                        }
                    }
                    continue
                }
                if (line.startsWith(":")) {
                    continue
                }
                if (line.startsWith("data:")) {
                    var rest = line[SSE_DATA_PREFIX_LEN..]
                    if (rest.size > 0 && rest[0] == 32) {
                        rest = rest[1..]
                    }
                    if (pending.size != 0) {
                        pending.append("\n")
                    }
                    pending.append(rest)
                }
            } else if (b != 0x0D) {
                lineBytes.add(b)
            }
        }
    }
    if (pending.size != 0) {
        processSseEvent(pending.toString(), sb, onChunk)
    }
    return sb.toString()
}

func decodeLine(bytes: ArrayList<Byte>): String {
    if (bytes.size == 0) {
        return ""
    }
    let arr = Array<Byte>(bytes.size, {i => bytes[i]})
    return String.fromUtf8(arr)
}

func processSseEvent(data: String, sb: StringBuilder, onChunk: ?StreamCallback): Bool {
    if (data == "[DONE]") {
        return true
    }
    try {
        let (content, _, _) = parseStreamChunk(data)
        if (!content.isEmpty()) {
            sb.append(content)
            match (onChunk) {
                case Some(cb) => cb(content)
                case None => ()
            }
        }
    } catch (_: Exception) {
        ()
    }
    return false
}
