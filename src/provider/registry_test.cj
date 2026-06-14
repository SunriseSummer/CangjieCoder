package cangjiecoder.provider

import std.unittest.*
import std.unittest.testmacro.*

@Test
class ProviderRegistryTests {
    @TestCase
    func hasFiveBuiltinProviders() {
        @Expect(allProviders().size, 5)
    }

    @TestCase
    func defaultIsHuawei() {
        @Expect(defaultProvider().id, "huawei")
    }

    @TestCase
    func findProviderById() {
        @Expect(findProvider("huawei").isSome(), true)
        @Expect(findProvider("kimi").isSome(), true)
        @Expect(findProvider("deepseek").isSome(), true)
        @Expect(findProvider("zhipu").isSome(), true)
        @Expect(findProvider("custom").isSome(), true)
    }

    @TestCase
    func findProviderIsCaseInsensitive() {
        @Expect(findProvider("HUAWEI").isSome(), true)
        @Expect(findProvider("DeepSeek").isSome(), true)
    }

    @TestCase
    func findProviderReturnsNoneForUnknown() {
        @Expect(findProvider("ghost").isNone(), true)
        @Expect(findProvider("").isNone(), true)
    }

    @TestCase
    func endpointsAreHttps() {
        for (provider in allProviders()) {
            if (provider.id == "custom") {
                continue
            }
            @Expect(provider.defaultEndpoint.startsWith("https://"), true)
        }
    }

    @TestCase
    func allProvidersHaveAtLeastOneModel() {
        for (provider in allProviders()) {
            @Expect(provider.models.size > 0, true)
        }
    }

    @TestCase
    func huaweiModels() {
        let huawei = findProvider("huawei").getOrThrow()
        @Expect(huawei.findModel("deepseek-v4-pro").isSome(), true)
        @Expect(huawei.findModel("glm-5.1").isSome(), true)
        @Expect(huawei.findModel("kimi-k2.6").isSome(), true)
        @Expect(huawei.findModel("not-real").isNone(), true)
    }

    @TestCase
    func defaultModelIsFirstEntry() {
        let deepseek = findProvider("deepseek").getOrThrow()
        @Expect(deepseek.defaultModel().id, deepseek.models[0].id)
    }
}
