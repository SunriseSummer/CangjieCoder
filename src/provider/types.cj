package cangjiecoder.provider

/**
 * 服务商 / 模型抽象
 *
 * - `ModelPreset`：单个模型条目（id + 友好名称）
 * - `ProviderPreset`：服务商配置（默认 endpoint + 支持模型列表）
 *
 * 所有内建服务商均使用 OpenAI 兼容的 `chat/completions` 接口
 */

public class ModelPreset {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        this.id = id
        this.displayName = displayName
    }
}

public class ProviderPreset {
    public let id: String
    public let displayName: String
    public let defaultEndpoint: String
    public let models: Array<ModelPreset>

    public init(id: String, displayName: String, defaultEndpoint: String, models: Array<ModelPreset>) {
        this.id = id
        this.displayName = displayName
        this.defaultEndpoint = defaultEndpoint
        this.models = models
    }

    public func findModel(id: String): ?ModelPreset {
        for (model in this.models) {
            if (model.id == id) {
                return model
            }
        }
        return None
    }

    public func defaultModel(): ModelPreset {
        return this.models[0]
    }
}
