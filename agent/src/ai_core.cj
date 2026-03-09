package cangjiecoderagent

import std.collection.*
import std.env.*
import std.io.*
import stdx.encoding.json.*
import stdx.net.http.*
import stdx.net.tls.*

// 保留有限的最近对话，既能给规划/总结补上下文，也避免会话无限膨胀。
const CONVERSATION_TURN_LIMIT: Int64 = 12

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
