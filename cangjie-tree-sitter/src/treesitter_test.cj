package cjtreesitter

@Test
class TreeSitterTest {
    @TestCase
    func parseSexpReturnsValidTree() {
        let source = "main() {\n    println(\"Hello\")\n}\n"
        let sexp = parseSexp(source)
        @Expect(!sexp.startsWith("error:"))
        @Expect(sexp.contains("translationUnit"))
        @Expect(sexp.contains("mainDefinition"))
    }

    @TestCase
    func parseSexpHandlesEmptySource() {
        let sexp = parseSexp("")
        @Expect(!sexp.startsWith("error:"))
        @Expect(sexp.contains("translationUnit"))
    }

    @TestCase
    func parseRootInfoReturnsCorrectType() {
        let source = "func hello(): Unit {}\n"
        let info = parseRootInfo(source)
        @Expect(info.nodeType, "translationUnit")
        @Expect(info.startRow, 0)
        @Expect(info.startColumn, 0)
        @Expect(info.isNamed)
    }

    @TestCase
    func queryNodesFindsMatches() {
        let source = "func a(): Unit {}\nfunc b(): Unit {}\n"
        let nodes = queryNodes(source, "functionDefinition")
        @Expect(nodes.size, 2)
        @Expect(nodes[0].nodeType, "functionDefinition")
        @Expect(nodes[1].nodeType, "functionDefinition")
    }

    @TestCase
    func queryNodesReturnsEmptyForNoMatch() {
        let source = "let x = 42\n"
        let nodes = queryNodes(source, "classDefinition")
        @Expect(nodes.size, 0)
    }

    @TestCase
    func listNamedNodesReturnsNamedOnly() {
        let source = "func hello(): Unit {}\n"
        let nodes = listNamedNodes(source, maxDepth: 2)
        @Expect(nodes.size > 0)
        for (node in nodes) {
            @Expect(node.isNamed)
        }
    }

    @TestCase
    func nodeInfoToJsonFormatsCorrectly() {
        let node = NodeInfo("functionDefinition", 0, 0, 1, 1, 0, 22, true, 3)
        let json = nodeInfoToJson(node)
        @Expect(json.contains("\"type\":\"functionDefinition\""))
        @Expect(json.contains("\"startRow\":0"))
        @Expect(json.contains("\"endRow\":1"))
        @Expect(json.contains("\"isNamed\":true"))
        @Expect(json.contains("\"childCount\":3"))
    }

    @TestCase
    func nodeInfoArrayToJsonFormatsCorrectly() {
        let nodes = [
            NodeInfo("a", 0, 0, 0, 1, 0, 1, true, 0),
            NodeInfo("b", 1, 0, 1, 1, 2, 3, true, 0)
        ]
        let json = nodeInfoArrayToJson(nodes)
        @Expect(json.startsWith("["))
        @Expect(json.endsWith("]"))
        @Expect(json.contains("\"type\":\"a\""))
        @Expect(json.contains("\"type\":\"b\""))
    }

    @TestCase
    func cangjieLanguageReturnsNonNull() {
        let lang = cangjieLanguage()
        @Expect(lang.isNotNull())
    }

    @TestCase
    func parseSexpWithExplicitLanguage() {
        let source = "main() {\n    println(\"Hello\")\n}\n"
        let sexp = parseSexp(source, language: cangjieLanguage())
        @Expect(!sexp.startsWith("error:"))
        @Expect(sexp.contains("translationUnit"))
    }
}
