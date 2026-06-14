package cangjiecoder.provider

/**
 * 内建服务商及模型清单
 *
 * 当前支持：
 *  - huawei   华为云 MaaS（仅 deepseek-v4-pro / glm-5.1 / kimi-k2.6）
 *  - kimi     月之暗面 Moonshot
 *  - deepseek DeepSeek
 *  - zhipu    智谱 GLM
 *  - custom   自定义 OpenAI 兼容接口（需配置 BaseURL 和 API Key）
 *
 * 所有服务商均使用 OpenAI 兼容的 `chat/completions` 接口（含 SSE 流式）
 * 用户可通过 `/connect` 切换服务商，并保存 API Key，通过 `/model` 切换当前模型
 */

let HUAWEI = ProviderPreset(
    "huawei",
    "华为云 MaaS",
    "https://api.modelarts-maas.com/v2/chat/completions",
    [
        ModelPreset("deepseek-v4-pro", "DeepSeek V4 Pro"),
        ModelPreset("glm-5.1", "GLM 5.1"),
        ModelPreset("kimi-k2.6", "Kimi K2.6")
    ]
)

let KIMI = ProviderPreset(
    "kimi",
    "月之暗面 Moonshot",
    "https://api.moonshot.cn/v1/chat/completions",
    [
        ModelPreset("kimi-k2.6", "Kimi K2.6"),
        ModelPreset("kimi-k2.5", "Kimi K2.5"),
        ModelPreset("kimi-k2-turbo-preview", "Kimi K2 Turbo Preview"),
        ModelPreset("kimi-latest", "Kimi Latest"),
        ModelPreset("moonshot-v1-128k", "Moonshot v1 128k"),
        ModelPreset("moonshot-v1-32k", "Moonshot v1 32k")
    ]
)

let DEEPSEEK = ProviderPreset(
    "deepseek",
    "DeepSeek",
    "https://api.deepseek.com/chat/completions",
    [
        ModelPreset("deepseek-v4-pro", "DeepSeek V4 Pro"),
        ModelPreset("deepseek-v4-flash", "DeepSeek V4 Flash"),
        ModelPreset("deepseek-reasoner", "DeepSeek Reasoner (R1)")
    ]
)

let ZHIPU = ProviderPreset(
    "zhipu",
    "智谱 GLM",
    "https://open.bigmodel.cn/api/paas/v4/chat/completions",
    [
        ModelPreset("glm-5.1", "GLM-5.1"),
        ModelPreset("glm-4.6", "GLM-4.6"),
        ModelPreset("glm-4-plus", "GLM-4-Plus"),
        ModelPreset("glm-4-air", "GLM-4-Air"),
        ModelPreset("glm-4-flash", "GLM-4-Flash")
    ]
)

let CUSTOM = ProviderPreset(
    "custom",
    "自定义 OpenAI 兼容接口",
    "",
    [
        ModelPreset("custom-model", "Custom Model")
    ]
)

let BUILTIN_PROVIDERS: Array<ProviderPreset> = [HUAWEI, KIMI, DEEPSEEK, ZHIPU, CUSTOM]

public func allProviders(): Array<ProviderPreset> {
    return BUILTIN_PROVIDERS
}

public func findProvider(id: String): ?ProviderPreset {
    let key = id.toAsciiLower()
    for (provider in BUILTIN_PROVIDERS) {
        if (provider.id == key) {
            return provider
        }
    }
    return None
}

public func defaultProvider(): ProviderPreset {
    return HUAWEI
}
