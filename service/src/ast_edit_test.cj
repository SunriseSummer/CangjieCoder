package cangjiecoder

import cangjiecoder.analysis.*

@Test
class AstEditTest {
    @TestCase
    func parseTreeSitterNodeMatchesExtractsRanges() {
        let sample = "(source_file [0, 0] - [2, 1]\n  (function_definition [0, 0] - [1, 1])\n  (function_definition [1, 0] - [2, 1]))"
        let matches = parseTreeSitterNodeMatches(sample, "function_definition")
        @Expect(matches.size, 2)
        @Expect(matches[0].startLine, 0)
        @Expect(matches[1].endLine, 2)
    }

    @TestCase
    func offsetForPointWalksNewlines() {
        let text = "ab\ncd"
        @Expect(offsetForPoint(text, 1, 0), 3)
        @Expect(offsetForPoint(text, 1, 2), 5)
    }
}
