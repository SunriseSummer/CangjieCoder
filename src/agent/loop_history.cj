package cangjiecoder.agent

import std.collection.*
import cangjiecoder.httpx.*

/**
 * 回滚到上一轮完整交互
 *
 * 移除最后一条 user 消息及其之后的 assistant/tool 消息
 */
func rollbackToLastUser(history: ArrayList<ChatMessage>): Unit {
    var lastUserIdx: Int64 = -1
    for (i in 0..history.size) {
        if (history[i].role == "user") {
            lastUserIdx = i
        }
    }
    if (lastUserIdx < 0) {
        return
    }
    while (history.size > lastUserIdx) {
        history.remove(at: history.size - 1)
    }
}

func buildRequestMessages(systemPrompt: String, history: ArrayList<ChatMessage>): ArrayList<ChatMessage> {
    let msgs = ArrayList<ChatMessage>()
    if (!systemPrompt.trimAscii().isEmpty()) {
        msgs.add(ChatMessage.system(systemPrompt))
    }
    for (msg in history) {
        msgs.add(msg)
    }
    return msgs
}
