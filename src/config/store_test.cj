package cangjiecoder.config

import std.unittest.*
import std.unittest.testmacro.*

@Test
class AppConfigTests {
    @TestCase
    func defaultsAreEmpty() {
        let config = AppConfig()
        @Expect(config.currentProvider, "")
        @Expect(config.currentModel, "")
        @Expect(config.systemPrompt, "")
        @Expect(config.credentials.size, 0)
    }

    @TestCase
    func setCredentialOverwrites() {
        let config = AppConfig()
        config.setCredential("p", "k1", "e1")
        config.setCredential("p", "k2", "e2")
        let cred = config.getCredential("p").getOrThrow()
        @Expect(cred.apiKey, "k2")
        @Expect(cred.endpoint, "e2")
    }

    @TestCase
    func getCredentialMissingReturnsNone() {
        let config = AppConfig()
        @Expect(config.getCredential("nope").isNone(), true)
    }
}

@Test
class SerializationTests {
    @TestCase
    func roundtripPreservesFields() {
        let c1 = AppConfig()
        c1.currentProvider = "deepseek"
        c1.currentModel = "deepseek-v4-pro"
        c1.systemPrompt = "你是专业开发者"
        c1.setCredential("deepseek", "sk-XYZ", "https://api.deepseek.com/chat/completions")
        c1.setCredential("kimi", "sk-KIMI", "https://api.moonshot.cn/v1/chat/completions")

        let text = serializeConfig(c1)
        let c2 = parseConfig(text)

        @Expect(c2.currentProvider, "deepseek")
        @Expect(c2.currentModel, "deepseek-v4-pro")
        @Expect(c2.systemPrompt, "你是专业开发者")
        @Expect(c2.credentials.size, 2)
        let deepseekCred = c2.getCredential("deepseek").getOrThrow()
        @Expect(deepseekCred.apiKey, "sk-XYZ")
        @Expect(deepseekCred.endpoint, "https://api.deepseek.com/chat/completions")
        let kimiCred = c2.getCredential("kimi").getOrThrow()
        @Expect(kimiCred.apiKey, "sk-KIMI")
    }

    @TestCase
    func parseEmptyCredentials() {
        let json = "{\"currentProvider\":\"x\",\"currentModel\":\"y\",\"systemPrompt\":\"\",\"credentials\":{}}"
        let config = parseConfig(json)
        @Expect(config.currentProvider, "x")
        @Expect(config.currentModel, "y")
        @Expect(config.credentials.size, 0)
    }

    @TestCase
    func parseTolerantOfMissingFields() {
        // 缺字段时不应抛异常，返回默认值
        let config = parseConfig("{}")
        @Expect(config.currentProvider, "")
        @Expect(config.credentials.size, 0)
    }

    @TestCase
    func parseCorruptedJsonReturnsDefaults() {
        // 修复前：损坏的 JSON 导致抛异常 crash
        // 修复后：loadConfig 中 try-catch 返回默认配置
        // 这里直接测试 parseConfig 应该抛异常（loadConfig 会捕获）
        var threw = false
        try {
            parseConfig("{broken json not valid")
        } catch (_: Exception) {
            threw = true
        }
        @Expect(threw, true)
    }

    @TestCase
    func serializedJsonIsValid() {
        let config = AppConfig()
        config.currentProvider = "a"
        config.currentModel = "b"
        let text = serializeConfig(config)
        // 必含必要字段
        @Expect(text.contains("currentProvider"), true)
        @Expect(text.contains("credentials"), true)
        // 解析回来不抛
        let c2 = parseConfig(text)
        @Expect(c2.currentProvider, "a")
    }
}
