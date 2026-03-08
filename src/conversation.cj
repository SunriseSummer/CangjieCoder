package cangjiecoder

import std.collection.*
import stdx.encoding.json.*

// Keep only a short rolling window so multi-turn memory stays useful without unbounded growth.
const CONVERSATION_TURN_LIMIT: Int64 = 12

struct ConversationTurn {
    public ConversationTurn(let role: String, let content: String) {}
}

class ConversationSession {
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
        while (turns.size > CONVERSATION_TURN_LIMIT) {
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
            lines.add("${turn.role}: ${shortPreview(turn.content, maxLines: 4)}")
        }
        return String.join(lines.toArray(), delimiter: "\n")
    }

    public func turnsJson(limit!: Int64 = 20): String {
        let array = JsonArray()
        for (turn in history(limit: limit)) {
            let item = JsonObject()
            item.put("role", JsonString(turn.role))
            item.put("content", JsonString(turn.content))
            array.add(item)
        }
        let root = JsonObject()
        root.put("sessionId", JsonString(sessionId))
        root.put("turns", array)
        return root.toString()
    }

    public prop turnCount: Int64 {
        get() {
            return turns.size
        }
    }
}

class ConversationStore {
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

    public func historyJson(sessionId: String): String {
        return getOrCreate(sessionId: sessionId).turnsJson()
    }
}
