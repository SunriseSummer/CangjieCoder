package cangjiecoderagent

import std.collection.*
import std.convert.*
import std.env.*
import std.fs.*
import std.io.*
import stdx.encoding.json.*
import stdx.net.http.*
import stdx.net.tls.*

// 保留有限的最近对话，既能给规划/总结补上下文，也避免会话无限膨胀。
const CONVERSATION_TURN_LIMIT: Int64 = 12

// Token 预算：粗略估算上下文 token 用量，避免超出模型窗口。
// 该值远小于主流模型实际窗口（32k–128k），留足空间给系统提示词和工具描述。
const TOKEN_BUDGET: Int64 = 8000

// 粗略估算文本的 token 数量。
// 算法：bytes / 3，是对英文（~4字符/token）和中文（~2字符/token）混合场景的折中。
// 注意：这是近似值，不同模型的实际 tokenizer 结果会有差异，
// 但足以在上下文滑动窗口中做安全截断决策。
func estimateTokenCount(text: String): Int64 {
    if (text.isEmpty()) {
        return 0
    }
    return (text.toArray().size + 2) / 3
}

struct ConversationTurn {
    public ConversationTurn(let role: String, let content: String) {}
}

struct ProviderSpec {
    public ProviderSpec(let name: String,
                        let displayName: String,
                        let baseUrl: String,
                        let apiKeyEnv: String,
                        let defaultModel: String) {}
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
        // 基于 token 预算进行智能截断，而非简单按轮次截断。
        // 优先淘汰最早的对话，保留最近交互的完整上下文。
        trimToTokenBudget()
    }

    // 按 token 预算淘汰最旧的对话轮次，直到总量降至安全阈值内。
    // 保持 CONVERSATION_TURN_LIMIT 作为硬上限兜底。
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
            lines.add("${turn.role}: ${shortPreview(turn.content, maxLines: 4)}")
        }
        return String.join(lines.toArray(), delimiter: "\n")
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

    // 将所有会话状态序列化为 JSON 并写入文件，支持崩溃后恢复。
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

    // 从 JSON 文件加载会话状态，恢复中断的任务上下文。
    public func loadFromFile(path: String): Unit {
        if (!exists(path)) {
            return
        }
        try {
            let content = String.fromUtf8(File.readFrom(path))
            let root = JsonValue.fromStr(content).asObject()
            let nextId = match (root.get("nextSessionId")) {
                case Some(value) => Int64.parse(value.toString())
                case None => nextSessionId
            }
            nextSessionId = nextId
            match (root.get("sessions")) {
                case Some(sessionsValue) =>
                    let sessionsObj = sessionsValue.asObject()
                    let fields = sessionsObj.getFields()
                    for ((id, turnsValue) in fields) {
                        let session = ConversationSession(id)
                        let turnsArr = turnsValue.asArray()
                        var index: Int64 = 0
                        while (index < turnsArr.size()) {
                            match (turnsArr.get(index)) {
                                case Some(turnValue) =>
                                    let turnObj = turnValue.asObject()
                                    let role = jsonField(turnObj, "role")
                                    let turnContent = jsonField(turnObj, "content")
                                    session.addTurn(role, turnContent)
                                case None => ()
                            }
                            index += 1
                        }
                        sessions[id] = session
                    }
                case None => ()
            }
        } catch (e: Exception) {
            // 文件损坏时静默忽略，从空状态重新开始
        }
    }
}

func builtinProviders(): Array<ProviderSpec> {
    return [
        ProviderSpec(
            "kimi",
            "Moonshot Kimi",
            "https://api.moonshot.cn/v1/chat/completions",
            "KIMI_API_KEY",
            "kimi-k2.5"
        ),
        ProviderSpec(
            "glm",
            "Zhipu GLM",
            "https://open.bigmodel.cn/api/paas/v4/chat/completions",
            "GLM_API_KEY",
            "glm-4.5"
        ),
        ProviderSpec(
            "openrouter",
            "OpenRouter",
            "https://openrouter.ai/api/v1/chat/completions",
            "OPENROUTER_API_KEY",
            "openrouter/free"
        )
    ]
}

func findProvider(name: String): ?ProviderSpec {
    let normalized = name.toAsciiLower().trimAscii()
    for (provider in builtinProviders()) {
        if (provider.name == normalized) {
            return provider
        }
    }
    return None
}

func listProvidersText(): String {
    let lines = ArrayList<String>()
    for (provider in builtinProviders()) {
        lines.add("${provider.name}: ${provider.displayName} (${provider.defaultModel})")
    }
    return String.join(lines.toArray(), delimiter: "\n")
}

func providerNamesText(): String {
    let names = ArrayList<String>()
    for (provider in builtinProviders()) {
        names.add(provider.name)
    }
    return String.join(names.toArray(), delimiter: ", ")
}

func providerResponseToText(body: String): String {
    try {
        let root = JsonValue.fromStr(body).asObject()
        if (let Some(choicesValue) <- root.get("choices")) {
            let choices = choicesValue.asArray()
            if (let Some(choiceValue) <- choices.get(0)) {
                let choice = choiceValue.asObject()
                if (let Some(messageValue) <- choice.get("message")) {
                    let message = messageValue.asObject()
                    if (let Some(contentValue) <- message.get("content")) {
                        match (contentValue.kind()) {
                            case JsString => return contentValue.asString().getValue()
                            case _ => return contentValue.toString()
                        }
                    }
                }
            }
        }
    } catch (e: Exception) {
        return body
    }
    return body
}

func providerReplySucceeded(reply: String): Bool {
    return !reply.startsWith("Missing API key:") &&
        !reply.startsWith("Unsupported provider:") &&
        !reply.startsWith("Provider request failed:")
}

func chatWithProvider(providerName: String,
                      model: String,
                      systemPrompt: String,
                      userPrompt: String): String {
    match (findProvider(providerName)) {
        case Some(provider) =>
            let apiKey = getVariable(provider.apiKeyEnv) ?? ""
            if (apiKey.isEmpty()) {
                return "Missing API key: set ${provider.apiKeyEnv}"
            }

            let actualModel = if (model.trimAscii().isEmpty()) {
                provider.defaultModel
            } else {
                model
            }

            let requestObject = JsonObject()
            requestObject.put("model", JsonString(actualModel))
            let messages = JsonArray()

            let systemMessage = JsonObject()
            systemMessage.put("role", JsonString("system"))
            systemMessage.put("content", JsonString(systemPrompt))
            messages.add(systemMessage)

            let userMessage = JsonObject()
            userMessage.put("role", JsonString("user"))
            userMessage.put("content", JsonString(userPrompt))
            messages.add(userMessage)

            requestObject.put("messages", messages)

            let clientBuilder = if (provider.baseUrl.startsWith("https://")) {
                let tlsConfig = TlsClientConfig()
                ClientBuilder().tlsConfig(tlsConfig)
            } else {
                ClientBuilder()
            }
            let client = clientBuilder.build()
            try {
                var requestBuilder = HttpRequestBuilder()
                    .post()
                    .url(provider.baseUrl)
                    .header("Content-Type", "application/json")
                    .header("Authorization", "Bearer ${apiKey}")
                if (provider.name == "openrouter") {
                    let referer = (getVariable("OPENROUTER_HTTP_REFERER") ?? "").trimAscii()
                    let title = (getVariable("OPENROUTER_APP_TITLE") ?? "").trimAscii()
                    if (!referer.isEmpty()) {
                        requestBuilder = requestBuilder.header("HTTP-Referer", referer)
                    }
                    if (!title.isEmpty()) {
                        requestBuilder = requestBuilder.header("X-Title", title)
                    }
                }
                let request = requestBuilder.body(requestObject.toString()).build()

                let response = client.send(request)
                let body = StringReader(response.body).readToEnd()
                client.close()
                return providerResponseToText(body)
            } catch (e: Exception) {
                client.close()
                return "Provider request failed: ${e}"
            }
        case None =>
            return "Unsupported provider: ${providerName}. Supported providers: ${providerNamesText()}"
    }
}

func planningSystemPrompt(): String {
    return "You are CangjieCoder Agent. Generate precise plans for Cangjie projects, prefer MCP-exposed LSP and AST tools for accurate code understanding, and keep actions bounded and surgical."
}

func reportingSystemPrompt(): String {
    return "You are CangjieCoder Agent. Summarize executed work in concise Chinese, grounded strictly in the provided execution transcript."
}

func conversationTurn(store: ConversationStore,
                      provider: String,
                      model: String,
                      systemPrompt: String,
                      prompt: String,
                      sessionId: String): ModelTurn {
    let session = store.getOrCreate(sessionId: sessionId)
    var effectiveSystemPrompt = systemPrompt
    let historyPrompt = session.buildPrompt(limit: 6)
    if (!historyPrompt.trimAscii().isEmpty()) {
        effectiveSystemPrompt = "${effectiveSystemPrompt}\n\nRecent conversation turns:\n${historyPrompt}"
    }
    let reply = chatWithProvider(provider, model, effectiveSystemPrompt, prompt)
    session.addTurn("user", prompt)
    session.addTurn("assistant", reply)
    return ModelTurn(reply, session.sessionId, providerReplySucceeded(reply))
}
