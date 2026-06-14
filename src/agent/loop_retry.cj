package cangjiecoder.agent

import cangjiecoder.httpx.*

let MAX_RETRIES: Int64 = 3

/**
 * 调用模型并对瞬时错误做指数退避重试
 *
 * 永久性错误直接外抛，由 REPL 或测试调用方处理
 */
func sendWithRetry(client: IChatClient, req: ChatRequest): (String, Array<ToolCall>, String) {
    var lastErr: Exception = Exception("")
    for (attempt in 0..=MAX_RETRIES) {
        try {
            return client.sendForMessage(req)
        } catch (e: Exception) {
            if (!isTransient(e)) {
                throw e
            }
            lastErr = e
            if (attempt < MAX_RETRIES) {
                let delaySec = Int64(1) << attempt
                eprintln("[retry] ${e.toString()} — ${delaySec}s 后重试 (${attempt + 1}/${MAX_RETRIES})")
                sleep(Duration.second * delaySec)
            }
        }
    }
    throw lastErr
}

func isTransient(ex: Exception): Bool {
    let errMsg = ex.toString()
    return errMsg.contains("Invalid utf8") || errMsg.contains("connection reset") || errMsg.contains("Connection reset") ||
        errMsg.contains("EOF") || errMsg.contains("read timeout") || errMsg.contains("response timeout") ||
        errMsg.contains("write timeout") || errMsg.contains("connection is closed")
}
