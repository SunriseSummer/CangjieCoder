package cangjiecoderagent

@Test
class AgentAiCoreTest {
    @TestCase
    func sessionStoresRecentTurns() {
        let session = ConversationSession("session-a")
        session.addTurn("user", "hello")
        session.addTurn("assistant", "world")
        @Expect(session.turnCount, 2)
        @Expect(session.buildPrompt().contains("user: hello"))
    }

    @TestCase
    func storeCreatesDistinctSessions() {
        let store = ConversationStore()
        let first = store.createSession()
        let second = store.createSession()
        @Expect(first.sessionId != second.sessionId)
    }

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
    func providerReplySucceededRejectsProviderFailures() {
        @Expect(!providerReplySucceeded("Missing API key: set OPENROUTER_API_KEY"))
        @Expect(!providerReplySucceeded("Unsupported provider: demo"))
        @Expect(!providerReplySucceeded("Provider request failed: timeout"))
        @Expect(providerReplySucceeded("正常回复"))
    }
}
