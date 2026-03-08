package cangjiecoder

import std.collection.*
import std.env.*
import std.io.*
import stdx.encoding.json.*
import stdx.net.http.*
import stdx.net.tls.*

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
                let request = HttpRequestBuilder()
                    .post()
                    .url(provider.baseUrl)
                    .header("Content-Type", "application/json")
                    .header("Authorization", "Bearer ${apiKey}")
                    .body(requestObject.toString())
                    .build()

                let response = client.send(request)
                let body = StringReader(response.body).readToEnd()
                client.close()
                return providerResponseToText(body)
            } catch (e: Exception) {
                client.close()
                return "Provider request failed: ${e}"
            }
        case None =>
            return "Unsupported provider: ${providerName}. Supported providers: kimi, glm"
    }
}
