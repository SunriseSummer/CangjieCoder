package cangjiecoder.config

import std.collection.*

/**
 * 应用配置数据结构`AppConfig` 仅承载状态，不参与 IO，
 * 序列化/反序列化由 `store.cj` 通过 stdx JSON 完成
 */

public class ProviderCredential {
    public var apiKey: String
    public var endpoint: String

    public init(apiKey: String, endpoint: String) {
        this.apiKey = apiKey
        this.endpoint = endpoint
    }
}

public class AppConfig {
    /** 当前选择的服务商 ID（如 "huawei"、"deepseek"） */
    public var currentProvider: String
    /** 当前选择的模型 ID（服务商内部模型 ID） */
    public var currentModel: String
    /** 各服务商凭证：providerId -> ProviderCredential */
    public var credentials: HashMap<String, ProviderCredential>
    /** 系统提示词 */
    public var systemPrompt: String

    public init() {
        this.currentProvider = ""
        this.currentModel = ""
        this.credentials = HashMap<String, ProviderCredential>()
        this.systemPrompt = ""
    }

    public func setCredential(providerId: String, apiKey: String, endpoint: String): Unit {
        this.credentials[providerId] = ProviderCredential(apiKey, endpoint)
    }

    public func getCredential(providerId: String): ?ProviderCredential {
        return this.credentials.get(providerId)
    }
}
