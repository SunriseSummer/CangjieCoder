package cangjiecoder

@Test
class ProviderSpecTest {
    @TestCase
    func builtinProvidersIncludeOpenRouter() {
        let provider = findProvider("openrouter")
        match (provider) {
            case Some(value) => @Expect(value.defaultModel, "openrouter/free")
            case None => @Expect(false)
        }
        @Expect(listProvidersText().contains("openrouter: OpenRouter (openrouter/free)"))
    }

    @TestCase
    func providerResponseSucceededRejectsProviderFailures() {
        @Expect(!providerReplySucceeded("Missing API key: set OPENROUTER_API_KEY"))
        @Expect(!providerReplySucceeded("Unsupported provider: demo"))
        @Expect(!providerReplySucceeded("Provider request failed: timeout"))
        @Expect(providerReplySucceeded("正常回复"))
    }
}
