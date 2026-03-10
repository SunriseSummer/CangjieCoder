// AI 对话管理：会话、token 预算、持久化
package cangjiecoderagent.ai

import std.collection.*
import std.convert.*
import std.fs.*
import stdx.encoding.json.*

// 保留有限的最近对话，既能给规划/总结补上下文，也避免会话无限膨胀。
public const CONVERSATION_TURN_LIMIT: Int64 = 12

// Token 预算：粗略估算上下文 token 用量，避免超出模型窗口。
// 该值远小于主流模型实际窗口（32k–128k），留足空间给系统提示词和工具描述。
public const TOKEN_BUDGET: Int64 = 8000

public struct ConversationTurn {
    public ConversationTurn(public let role: String, public let content: String) {}
}

// 粗略估算文本的 token 数量。
// 算法：bytes / 3，是对英文（~4字符/token）和中文（~2字符/token）混合场景的折中。
public func estimateTokenCount(text: String): Int64 {
    if (text.isEmpty()) {
        return 0
    }
    return (text.toArray().size + 2) / 3
}

public class ConversationSession {
    public let sessionId: String
    let turns = ArrayList<ConversationTurn>()

    public init(sessionId: String) {
        this.sessionId = sessionId
    }

    public func addTurn(role: String, content: String): Unit {
        if (content.trimAscii().isEmpty()) {
            return
        }
        turns.add(ConversationTurn(role, content))
        trimToTokenBudget()
    }

    // 按 token 预算淘汰最旧的对话轮次，直到总量降至安全阈值内。
    func trimToTokenBudget(): Unit {
        while (turns.size > CONVERSATION_TURN_LIMIT) {
            turns.remove(at: 0)
        }
        while (turns.size > 1) {
            var total: Int64 = 0
            for (turn in turns) {
                total += estimateTokenCount(turn.content)
            }
            if (total <= TOKEN_BUDGET) {
                break
            }
            turns.remove(at: 0)
        }
    }

    public func history(limit!: Int64 = 6): Array<ConversationTurn> {
        let results = ArrayList<ConversationTurn>()
        let start = if (turns.size > limit) { turns.size - limit } else { 0 }
        for (index in start..turns.size) {
            results.add(turns[index])
        }
        return results.toArray()
    }

    public func buildPrompt(limit!: Int64 = 6): String {
        let lines = ArrayList<String>()
        for (turn in history(limit: limit)) {
            lines.add("${turn.role}: ${aiShortPreview(turn.content, maxLines: 4)}")
        }
        return String.join(lines.toArray(), delimiter: "\n")
    }

    public prop turnCount: Int64 {
        get() {
            return turns.size
        }
    }
}

// 从 JSON 数组反序列化对话轮次到指定会话
public func deserializeSessionTurns(session: ConversationSession, turnsArr: JsonArray): Unit {
    var index: Int64 = 0
    while (index < turnsArr.size()) {
        match (turnsArr.get(index)) {
            case Some(turnValue) =>
                let turnObj = turnValue.asObject()
                session.addTurn(aiJsonField(turnObj, "role"), aiJsonField(turnObj, "content"))
            case None => ()
        }
        index += 1
    }
}

// 从已解析的 JSON 根对象恢复所有会话
public func deserializeSessions(sessions: HashMap<String, ConversationSession>, root: JsonObject): Unit {
    match (root.get("sessions")) {
        case Some(sessionsValue) =>
            let fields = sessionsValue.asObject().getFields()
            for ((id, turnsValue) in fields) {
                let session = ConversationSession(id)
                deserializeSessionTurns(session, turnsValue.asArray())
                sessions[id] = session
            }
        case None => ()
    }
}

public class ConversationStore {
    let sessions = HashMap<String, ConversationSession>()
    var nextSessionId: Int64 = 1

    public func createSession(): ConversationSession {
        let session = ConversationSession("session-${nextSessionId}")
        nextSessionId += 1
        sessions[session.sessionId] = session
        return session
    }

    public func getOrCreate(sessionId!: String = ""): ConversationSession {
        let normalized = sessionId.trimAscii()
        if (normalized.isEmpty()) {
            return createSession()
        }
        match (sessions.get(normalized)) {
            case Some(session) =>
                return session
            case None =>
                let created = ConversationSession(normalized)
                sessions[normalized] = created
                return created
        }
    }

    public func saveToFile(path: String): Unit {
        let root = JsonObject()
        root.put("nextSessionId", JsonInt(nextSessionId))
        let sessionsJson = JsonObject()
        for ((id, session) in sessions) {
            let turnsJson = JsonArray()
            for (turn in session.history(limit: CONVERSATION_TURN_LIMIT)) {
                let turnJson = JsonObject()
                turnJson.put("role", JsonString(turn.role))
                turnJson.put("content", JsonString(turn.content))
                turnsJson.add(turnJson)
            }
            sessionsJson.put(id, turnsJson)
        }
        root.put("sessions", sessionsJson)
        let parentDir = Path(path).parent.toString()
        if (!parentDir.isEmpty() && !exists(parentDir)) {
            Directory.create(parentDir, recursive: true)
        }
        File.writeTo(path, root.toString().toArray())
    }

    public func loadFromFile(path: String): Unit {
        if (!exists(path)) {
            return
        }
        try {
            let content = String.fromUtf8(File.readFrom(path))
            let root = JsonValue.fromStr(content).asObject()
            match (root.get("nextSessionId")) {
                case Some(value) => nextSessionId = Int64.parse(value.toString())
                case None => ()
            }
            deserializeSessions(sessions, root)
        } catch (e: Exception) {
            // 文件损坏时静默忽略，从空状态重新开始
        }
    }
}

// 子包内部工具函数副本（避免对根包循环依赖）
func aiShortPreview(text: String, maxLines!: Int64 = 8): String {
    let lines = ArrayList<String>()
    var count = 0
    for (line in text.lines()) {
        if (line.trimAscii().isEmpty()) {
            continue
        }
        lines.add(line)
        count += 1
        if (count >= maxLines) {
            break
        }
    }
    return String.join(lines.toArray(), delimiter: "\n")
}

func aiJsonField(obj: JsonObject, key: String, fallback!: String = ""): String {
    match (obj.get(key)) {
        case Some(value) =>
            match (value.kind()) {
                case JsString => return value.asString().getValue()
                case _ => return value.toString()
            }
        case None =>
            return fallback
    }
}
