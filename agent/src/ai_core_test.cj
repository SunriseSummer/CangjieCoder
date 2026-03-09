package cangjiecoderagent

import std.env.*
import std.fs.*

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

    @TestCase
    func estimateTokenCountReturnsZeroForEmpty() {
        @Expect(estimateTokenCount(""), 0)
    }

    @TestCase
    func estimateTokenCountApproximatesEnglish() {
        // "hello world" = 11 bytes, estimate ~4 tokens
        let tokens = estimateTokenCount("hello world")
        @Expect(tokens > 0)
        @Expect(tokens < 20)
    }

    @TestCase
    func tokenBudgetTruncatesLargeConversations() {
        let session = ConversationSession("session-budget")
        // 每轮添加大量内容，测试 token 预算截断
        let largeContent = String.fromUtf8(Array<Byte>(10000, repeat: 65))
        for (_ in 0..5) {
            session.addTurn("user", "${largeContent}")
            session.addTurn("assistant", "${largeContent}")
        }
        // 应该由于 token 预算限制而截断，不会保留全部 10 轮
        @Expect(session.turnCount < 10)
        @Expect(session.turnCount > 0)
    }

    @TestCase
    func tokenBudgetKeepsAtLeastOneTurn() {
        let session = ConversationSession("session-min")
        let hugeContent = String.fromUtf8(Array<Byte>(50000, repeat: 66))
        session.addTurn("user", hugeContent)
        // 即使单轮内容超出预算，也至少保留 1 轮
        @Expect(session.turnCount, 1)
    }

    @TestCase
    func conversationStoreSaveAndLoadRoundTrip() {
        let tempDir = Directory.createTemp(getTempDirectory())
        let filePath = "${tempDir.toString()}/sessions.json"
        try {
            let store = ConversationStore()
            let session = store.createSession()
            session.addTurn("user", "test prompt")
            session.addTurn("assistant", "test response")
            store.saveToFile(filePath)

            let loadedStore = ConversationStore()
            loadedStore.loadFromFile(filePath)
            let loadedSession = loadedStore.getOrCreate(sessionId: session.sessionId)
            @Expect(loadedSession.turnCount, 2)
            @Expect(loadedSession.buildPrompt().contains("test prompt"))
        } finally {
            removeIfExists(tempDir.toString(), recursive: true)
        }
    }

    @TestCase
    func conversationStoreLoadIgnoresCorruptFile() {
        let tempDir = Directory.createTemp(getTempDirectory())
        let filePath = "${tempDir.toString()}/bad.json"
        try {
            File.writeTo(filePath, "not valid json{{{".toArray())
            let store = ConversationStore()
            store.loadFromFile(filePath)
            // 文件损坏时不应抛出异常，从空状态开始
            @Expect(store.createSession().sessionId.contains("session-"))
        } finally {
            removeIfExists(tempDir.toString(), recursive: true)
        }
    }

    @TestCase
    func conversationStoreLoadSkipsMissingFile() {
        let store = ConversationStore()
        store.loadFromFile("/tmp/nonexistent-conversation-store-12345.json")
        // 文件不存在时不应抛出异常
        @Expect(store.createSession().sessionId.contains("session-"))
    }
}
