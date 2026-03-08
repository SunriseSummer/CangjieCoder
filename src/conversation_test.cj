package cangjiecoder

@Test
class ConversationSessionTest {
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
}
