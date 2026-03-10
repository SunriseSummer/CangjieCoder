package cangjiecoder

import std.env.*
import std.fs.*
import cangjiecoder.common.*
import cangjiecoder.json.*
import cangjiecoder.mcp.*
import cangjiecoder.ast.*

@Test
class AstServiceTest {
    @TestCase
    func treeSitterParseSexpReturnsValidTree() {
        let source = "main() {\n    println(\"Hello\")\n}\n"
        let sexp = treeSitterParseSexp(source)
        @Expect(!sexp.startsWith("error:"))
        @Expect(sexp.contains("translationUnit"))
        @Expect(sexp.contains("mainDefinition"))
    }

    @TestCase
    func treeSitterParseSexpHandlesEmptySource() {
        let sexp = treeSitterParseSexp("")
        @Expect(!sexp.startsWith("error:"))
        @Expect(sexp.contains("translationUnit"))
    }

    @TestCase
    func treeSitterParseRootInfoReturnsCorrectType() {
        let source = "func hello(): Unit {}\n"
        let info = treeSitterParseRootInfo(source)
        @Expect(info.nodeType, "translationUnit")
        @Expect(info.startRow, 0)
        @Expect(info.startColumn, 0)
        @Expect(info.isNamed)
    }

    @TestCase
    func treeSitterQueryNodesFindsMatches() {
        let source = "func a(): Unit {}\nfunc b(): Unit {}\n"
        let nodes = treeSitterQueryNodes(source, "functionDefinition")
        @Expect(nodes.size, 2)
        @Expect(nodes[0].nodeType, "functionDefinition")
        @Expect(nodes[1].nodeType, "functionDefinition")
    }

    @TestCase
    func treeSitterQueryNodesReturnsEmptyForNoMatch() {
        let source = "let x = 42\n"
        let nodes = treeSitterQueryNodes(source, "classDefinition")
        @Expect(nodes.size, 0)
    }

    @TestCase
    func treeSitterListNamedNodesReturnsNamedOnly() {
        let source = "func hello(): Unit {}\n"
        let nodes = treeSitterListNamedNodes(source, maxDepth: 2)
        @Expect(nodes.size > 0)
        for (node in nodes) {
            @Expect(node.isNamed)
        }
    }

    @TestCase
    func astNodeInfoToJsonFormatsCorrectly() {
        let node = AstNodeInfo("functionDefinition", 0, 0, 1, 1, 0, 22, true, 3)
        let json = astNodeInfoToJson(node)
        @Expect(json.contains("\"type\":\"functionDefinition\""))
        @Expect(json.contains("\"startRow\":0"))
        @Expect(json.contains("\"endRow\":1"))
        @Expect(json.contains("\"isNamed\":true"))
        @Expect(json.contains("\"childCount\":3"))
    }

    @TestCase
    func astNodeInfoArrayToJsonFormatsCorrectly() {
        let nodes = [
            AstNodeInfo("a", 0, 0, 0, 1, 0, 1, true, 0),
            AstNodeInfo("b", 1, 0, 1, 1, 2, 3, true, 0)
        ]
        let json = astNodeInfoArrayToJson(nodes)
        @Expect(json.startsWith("["))
        @Expect(json.endsWith("]"))
        @Expect(json.contains("\"type\":\"a\""))
        @Expect(json.contains("\"type\":\"b\""))
    }

    @TestCase
    func mcpAstParseToolReturnsAstViaToolsCall() {
        let workspace = Directory.createTemp(getTempDirectory())
        try {
            let filePath = "${workspace.toString()}/demo.cj"
            writeTextFile(filePath, "main() {\n    println(\"Hello\")\n}\n")
            let runtime = createMcpRuntime(workspace.toString(), serviceRoot: getWorkingDirectory().toString())
            let response = runtime.handleRequest(
                "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"cangjie.ast_parse\",\"arguments\":{\"path\":\"demo.cj\"}}}"
            )
            match (response) {
                case Some(payload) =>
                    @Expect(payload.contains("\"ok\":true"))
                    @Expect(payload.contains("translationUnit"))
                case None =>
                    @Expect(false)
            }
        } finally {
            removeIfExists(workspace.toString(), recursive: true)
        }
    }

    @TestCase
    func mcpAstQueryNodesToolReturnsMatchedNodes() {
        let workspace = Directory.createTemp(getTempDirectory())
        try {
            let filePath = "${workspace.toString()}/funcs.cj"
            writeTextFile(filePath, "func a(): Unit {}\nfunc b(): Unit {}\n")
            let runtime = createMcpRuntime(workspace.toString(), serviceRoot: getWorkingDirectory().toString())
            let response = runtime.handleRequest(
                "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"cangjie.ast_query_nodes\",\"arguments\":{\"path\":\"funcs.cj\",\"nodeType\":\"functionDefinition\"}}}"
            )
            match (response) {
                case Some(payload) =>
                    @Expect(payload.contains("\"ok\":true"))
                    @Expect(payload.contains("\"matchCount\":2"))
                case None =>
                    @Expect(false)
            }
        } finally {
            removeIfExists(workspace.toString(), recursive: true)
        }
    }

    @TestCase
    func mcpAstListNodesToolReturnsNamedNodes() {
        let workspace = Directory.createTemp(getTempDirectory())
        try {
            let filePath = "${workspace.toString()}/list.cj"
            writeTextFile(filePath, "func hello(): Unit {}\n")
            let runtime = createMcpRuntime(workspace.toString(), serviceRoot: getWorkingDirectory().toString())
            let response = runtime.handleRequest(
                "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"cangjie.ast_list_nodes\",\"arguments\":{\"path\":\"list.cj\"}}}"
            )
            match (response) {
                case Some(payload) =>
                    @Expect(payload.contains("\"ok\":true"))
                    @Expect(payload.contains("\"nodeCount\""))
                case None =>
                    @Expect(false)
            }
        } finally {
            removeIfExists(workspace.toString(), recursive: true)
        }
    }

    @TestCase
    func toolRegistryIncludesAstTools() {
        let registry = buildMcpToolRegistry()
        @Expect(registry.contains("cangjie.ast_parse"))
        @Expect(registry.contains("cangjie.ast_query_nodes"))
        @Expect(registry.contains("cangjie.ast_list_nodes"))
    }

    @TestCase
    func toolDefinitionsIncludeAstTools() {
        let json = toolDefinitionsJson()
        @Expect(json.contains("cangjie.ast_parse"))
        @Expect(json.contains("cangjie.ast_query_nodes"))
        @Expect(json.contains("cangjie.ast_list_nodes"))
    }
}
