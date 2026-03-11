package cangjiecoder

import std.env.*
import std.fs.*
import cangjiecoder.common.*
import cangjiecoder.json.*
import cangjiecoder.lsp.*

func restoreVariable(key: String, previousValue: ?String): Unit {
    match (previousValue) {
        case Some(value) => setVariable(key, value)
        case None => removeVariable(key)
    }
}

func fakeLspServerScript(tempRoot: String, responseBody: String): String {
    let scriptPath = "${tempRoot}/fake-lsp.sh"
    // 这里显式拆开 `$` 与 `{#body}`，避免仓颉字符串插值把 bash 变量长度展开误判成自身语法。
    let bashBodyLengthRef = "$" + "{#body}"
    let scriptLines = [
        "#!/usr/bin/env bash",
        "body='${responseBody}'",
        "printf 'Content-Length: %s\\r\\n\\r\\n%s' \"${bashBodyLengthRef}\" \"$body\"",
        ""
    ]
    let script = String.join(scriptLines, delimiter: "\n")
    writeTextFile(scriptPath, script)
    let (_, _, stderr) = runCommandDetailedOutput("chmod", ["+x", scriptPath], tempRoot)
    if (!stderr.trimAscii().isEmpty()) {
        throw IllegalArgumentException("Failed to chmod fake LSP server: ${stderr}")
    }
    return scriptPath
}

@Test
class LspProtocolTest {
    @TestCase
    func extractLspBodiesParsesFramedResponses() {
        let payload = "${encodeLspFrame("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"capabilities\":{}}}")}${encodeLspFrame("{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":null}")}"
        let bodies = extractLspBodies(payload)
        @Expect(bodies.size, 2)
        @Expect(bodies[0].contains("\"capabilities\""))
    }

    @TestCase
    func fileUriEscapesWhitespace() {
        let path = "${getWorkingDirectory().toString()}/target/test file.cj"
        removeIfExists(path)
        writeTextFile(path, "main() {}")
        let uri = fileUri(path)
        @Expect(uri.startsWith("file://"))
        @Expect(uri.contains("%20"))
        removeIfExists(path)
    }

    @TestCase
    func lspWorkspaceSymbolsReportsUnavailableWhenDiscoveryFails() {
        let previousCommand = getVariable("CANGJIE_LSP_COMMAND")
        let previousSdkHome = getVariable("CANGJIE_SDK_HOME")
        let previousPath = getVariable("PATH")
        removeVariable("CANGJIE_LSP_COMMAND")
        removeVariable("CANGJIE_SDK_HOME")
        setVariable("PATH", "/usr/bin:/bin")
        clearLspCommandCache()
        closeLspSession()
        let result = queryLspWorkspaceSymbols(getWorkingDirectory().toString(), "JsonParser")
        @Expect(!result.available)
        @Expect(result.summary.contains("No Cangjie LSP binary"))
        restoreVariable("CANGJIE_LSP_COMMAND", previousCommand)
        restoreVariable("CANGJIE_SDK_HOME", previousSdkHome)
        restoreVariable("PATH", previousPath)
        clearLspCommandCache()
    }

    @TestCase
    func lspDefinitionReadsStructuredResponseFromFakeServer() {
        let workspace = Directory.createTemp(getTempDirectory())
        Directory.create("${workspace.toString()}/src", recursive: true)
        let sourcePath = "${workspace.toString()}/src/demo.cj"
        writeTextFile(sourcePath, "package demo\n\nfunc call(): Unit {\n    target()\n}\n\nfunc target(): Unit {}\n")
        let responseBody = "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":[{\"uri\":\"${fileUri(sourcePath)}\",\"range\":{\"start\":{\"line\":5,\"character\":0},\"end\":{\"line\":5,\"character\":6}}}]}"
        let previousCommand = getVariable("CANGJIE_LSP_COMMAND")
        let previousSdkHome = getVariable("CANGJIE_SDK_HOME")
        setVariable("CANGJIE_LSP_COMMAND", fakeLspServerScript(workspace.toString(), responseBody))
        removeVariable("CANGJIE_SDK_HOME")
        clearLspCommandCache()
        closeLspSession()
        let result = queryLspDefinition(workspace.toString(), "src/demo.cj", 2, 4)
        @Expect(result.available)
        @Expect(result.success)
        @Expect(result.method, "textDocument/definition")
        @Expect(result.resultJson.contains("\"uri\""))
        restoreVariable("CANGJIE_LSP_COMMAND", previousCommand)
        restoreVariable("CANGJIE_SDK_HOME", previousSdkHome)
        clearLspCommandCache()
        closeLspSession()
        removeIfExists(workspace.toString(), recursive: true)
    }
}
