// 代码质量优化专项测试：覆盖 analyzer、json helpers、lsp、mcp 协议等模块
package cangjiecoder

import std.collection.*
import std.env.*
import std.fs.*
import cangjiecoder.analysis.*
import cangjiecoder.common.*
import cangjiecoder.json.*
import cangjiecoder.lsp.*
import cangjiecoder.mcp.*
import cangjiecoder.tools.*
import stdx.encoding.json.*

@Test
class AnalyzerExtendedTest {
    // ── parseTreeSitterNodeMatches 测试 ──────────────

    @TestCase
    func parseNodeMatchesHandlesEmptyOutput() {
        // 空输出应返回空数组
        let matches = parseTreeSitterNodeMatches("", "function_definition")
        @Expect(matches.size, 0)
    }

    @TestCase
    func parseNodeMatchesIgnoresUnrelatedLines() {
        // 不包含目标节点类型的行应被跳过
        let output = "(source_file [0, 0] - [5, 0]\n  (class_definition [0, 0] - [5, 0]))"
        let matches = parseTreeSitterNodeMatches(output, "function_definition")
        @Expect(matches.size, 0)
    }

    @TestCase
    func parseNodeMatchesParsesMultipleMatches() {
        // 应正确解析多个匹配节点的坐标
        let output = "  (function_definition [0, 0] - [2, 1])\n  (function_definition [3, 0] - [5, 1])\n  (function_definition [6, 0] - [8, 1])"
        let matches = parseTreeSitterNodeMatches(output, "function_definition")
        @Expect(matches.size, 3)
        @Expect(matches[0].startLine, 0)
        @Expect(matches[1].startLine, 3)
        @Expect(matches[2].startLine, 6)
        @Expect(matches[2].endLine, 8)
        @Expect(matches[2].endColumn, 1)
    }

    @TestCase
    func parseNodeMatchesSkipsMalformedLines() {
        // 格式不正确的行应被静默跳过
        let output = "  (function_definition [0, 0] - [2, 1])\n  (function_definition [bad, format])\n  (function_definition [4, 0] - [6, 1])"
        let matches = parseTreeSitterNodeMatches(output, "function_definition")
        @Expect(matches.size, 2)
    }

    // ── offsetForPoint 测试 ──────────────────────────

    @TestCase
    func offsetForPointHandlesFirstPosition() {
        // 文件起始位置的偏移量应为 0
        @Expect(offsetForPoint("hello", 0, 0), 0)
    }

    @TestCase
    func offsetForPointHandlesCRLF() {
        // 应正确处理 CRLF 换行（2 字节换行符）
        let text = "ab\r\ncd"
        @Expect(offsetForPoint(text, 1, 0), 4)
        @Expect(offsetForPoint(text, 1, 1), 5)
    }

    @TestCase
    func offsetForPointHandlesEndOfFile() {
        // 文件末尾位置应返回文件长度
        let text = "ab"
        @Expect(offsetForPoint(text, 0, 2), 2)
    }

    @TestCase
    func offsetForPointHandlesMultipleNewlines() {
        // 多行文本中的坐标转换
        let text = "line1\nline2\nline3"
        @Expect(offsetForPoint(text, 0, 0), 0)
        @Expect(offsetForPoint(text, 1, 0), 6)
        @Expect(offsetForPoint(text, 2, 0), 12)
        @Expect(offsetForPoint(text, 2, 5), 17)
    }

    // ── sliceText 测试 ──────────────────────────────

    @TestCase
    func sliceTextReturnsEmptyForInvalidRange() {
        // 无效范围应返回空字符串
        @Expect(sliceText("hello", 3, 2), "")
        @Expect(sliceText("hello", 5, 5), "")
    }

    @TestCase
    func sliceTextReturnsCorrectSubstring() {
        @Expect(sliceText("hello world", 0, 5), "hello")
        @Expect(sliceText("hello world", 6, 11), "world")
    }

    // ── astEditSucceeded 测试 ────────────────────────

    @TestCase
    func astEditSucceededRecognizesSuccess() {
        @Expect(astEditSucceeded("updated AST node func at main.cj:0:0"))
    }

    @TestCase
    func astEditSucceededRecognizesFailures() {
        @Expect(!astEditSucceeded("tree-sitter unavailable for AST edit"))
        @Expect(!astEditSucceeded("No AST node matched type xyz"))
        @Expect(!astEditSucceeded("Path does not exist: bad.cj"))
        @Expect(!astEditSucceeded("Path escapes repository root: ../hack"))
    }
}

@Test
class JsonHelpersExtendedTest {
    // ── jsonField 测试 ──────────────────────────────

    @TestCase
    func jsonFieldReturnsStringValue() {
        let obj = JsonObject()
        obj.put("name", JsonString("test"))
        @Expect(jsonField(obj, "name"), "test")
    }

    @TestCase
    func jsonFieldReturnsFallbackForMissingKey() {
        let obj = JsonObject()
        @Expect(jsonField(obj, "missing"), "")
        @Expect(jsonField(obj, "missing", fallback: "default"), "default")
    }

    @TestCase
    func jsonFieldConvertsNonStringTypes() {
        let obj = JsonObject()
        obj.put("count", JsonInt(42))
        obj.put("flag", JsonBool(true))
        @Expect(jsonField(obj, "count"), "42")
        @Expect(jsonField(obj, "flag"), "true")
    }

    // ── parseJsonObject 测试 ────────────────────────

    @TestCase
    func parseJsonObjectHandlesEmptyString() {
        // 空字符串应返回空对象
        let obj = parseJsonObject("")
        @Expect(obj.getFields().size, 0)
    }

    @TestCase
    func parseJsonObjectHandlesWhitespace() {
        // 仅含空白的字符串应返回空对象
        let obj = parseJsonObject("   \n\t  ")
        @Expect(obj.getFields().size, 0)
    }

    @TestCase
    func parseJsonObjectParsesValidJson() {
        let obj = parseJsonObject("{\"key\":\"value\"}")
        @Expect(jsonField(obj, "key"), "value")
    }

    // ── parseJsonIntField 测试 ──────────────────────

    @TestCase
    func parseJsonIntFieldParsesIntegers() {
        let obj = JsonObject()
        obj.put("port", JsonInt(8080))
        @Expect(parseJsonIntField(obj, "port"), 8080)
    }

    @TestCase
    func parseJsonIntFieldReturnsFallbackForMissing() {
        let obj = JsonObject()
        @Expect(parseJsonIntField(obj, "missing"), 0)
        @Expect(parseJsonIntField(obj, "missing", fallback: -1), -1)
    }

    @TestCase
    func parseJsonIntFieldReturnsFallbackForInvalid() {
        let obj = JsonObject()
        obj.put("bad", JsonString("not_a_number"))
        @Expect(parseJsonIntField(obj, "bad"), 0)
    }

    // ── parseJsonBoolField 测试 ─────────────────────

    @TestCase
    func parseJsonBoolFieldParsesTrue() {
        let obj = JsonObject()
        obj.put("enabled", JsonBool(true))
        @Expect(parseJsonBoolField(obj, "enabled"), true)
    }

    @TestCase
    func parseJsonBoolFieldParsesFalse() {
        let obj = JsonObject()
        obj.put("enabled", JsonBool(false))
        @Expect(parseJsonBoolField(obj, "enabled"), false)
    }

    @TestCase
    func parseJsonBoolFieldReturnsFallbackForMissing() {
        let obj = JsonObject()
        @Expect(parseJsonBoolField(obj, "missing"), false)
        @Expect(parseJsonBoolField(obj, "missing", fallback: true), true)
    }

    @TestCase
    func parseJsonBoolFieldHandlesInvalidValue() {
        let obj = JsonObject()
        obj.put("weird", JsonString("maybe"))
        @Expect(parseJsonBoolField(obj, "weird"), false)
        @Expect(parseJsonBoolField(obj, "weird", fallback: true), true)
    }

    // ── jsonStringArrayField 测试 ───────────────────

    @TestCase
    func jsonStringArrayFieldReturnsEmptyForMissingKey() {
        let obj = JsonObject()
        let arr = jsonStringArrayField(obj, "tags")
        @Expect(arr.size, 0)
    }

    @TestCase
    func jsonStringArrayFieldHandlesSingleString() {
        // 单个字符串值应包装为单元素数组
        let obj = JsonObject()
        obj.put("tags", JsonString("cangjie"))
        let arr = jsonStringArrayField(obj, "tags")
        @Expect(arr.size, 1)
        @Expect(arr[0], "cangjie")
    }

    @TestCase
    func jsonStringArrayFieldHandlesArray() {
        let obj = JsonObject()
        let jsonArr = JsonArray()
        jsonArr.add(JsonString("a"))
        jsonArr.add(JsonString("b"))
        jsonArr.add(JsonString("c"))
        obj.put("tags", jsonArr)
        let arr = jsonStringArrayField(obj, "tags")
        @Expect(arr.size, 3)
        @Expect(arr[0], "a")
        @Expect(arr[2], "c")
    }

    @TestCase
    func jsonStringArrayFieldHandlesMixedTypes() {
        // 数组中的非字符串元素应转为 toString
        let obj = JsonObject()
        let jsonArr = JsonArray()
        jsonArr.add(JsonString("text"))
        jsonArr.add(JsonInt(42))
        obj.put("mixed", jsonArr)
        let arr = jsonStringArrayField(obj, "mixed")
        @Expect(arr.size, 2)
        @Expect(arr[0], "text")
        @Expect(arr[1], "42")
    }

    // ── toolResultJson 测试 ─────────────────────────

    @TestCase
    func toolResultJsonFormatsCorrectly() {
        let result = toolResultJson(true, "Operation succeeded")
        @Expect(result.contains("\"ok\":true"))
        @Expect(result.contains("\"summary\":\"Operation succeeded\""))
    }

    @TestCase
    func toolResultJsonFormatsFailure() {
        let result = toolResultJson(false, "Operation failed")
        @Expect(result.contains("\"ok\":false"))
    }

    // ── toolMessageJson 测试 ────────────────────────

    @TestCase
    func toolMessageJsonIncludesMessage() {
        let result = toolMessageJson(true, "Done", "File created successfully")
        @Expect(result.contains("\"message\":\"File created successfully\""))
        @Expect(result.contains("\"ok\":true"))
    }

    // ── toolCommandResultJson 测试 ──────────────────

    @TestCase
    func toolCommandResultJsonFormatsSuccessfulCommand() {
        let result = toolCommandResultJson("echo", ["hello"], "/tmp", 0, "hello\n", "", maxLines: 10)
        @Expect(result.contains("\"ok\":true"))
        @Expect(result.contains("Command succeeded: echo"))
        @Expect(result.contains("\"exitCode\":0"))
    }

    @TestCase
    func toolCommandResultJsonFormatsFailedCommand() {
        let result = toolCommandResultJson("false", [], "/tmp", 1, "", "error\n", maxLines: 10)
        @Expect(result.contains("\"ok\":false"))
        @Expect(result.contains("Command failed: false"))
        @Expect(result.contains("\"exitCode\":1"))
    }
}

@Test
class LspProtocolExtendedTest {
    // ── encodeLspFrame / extractLspBodies 往返测试 ──

    @TestCase
    func lspFrameRoundTripPreservesContent() {
        let body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}"
        let frame = encodeLspFrame(body)
        let bodies = extractLspBodies(frame)
        @Expect(bodies.size, 1)
        @Expect(bodies[0], body)
    }

    @TestCase
    func lspFrameRoundTripHandlesMultipleFrames() {
        let body1 = "{\"id\":1}"
        let body2 = "{\"id\":2}"
        let body3 = "{\"id\":3}"
        let combined = "${encodeLspFrame(body1)}${encodeLspFrame(body2)}${encodeLspFrame(body3)}"
        let bodies = extractLspBodies(combined)
        @Expect(bodies.size, 3)
        @Expect(bodies[0], body1)
        @Expect(bodies[2], body3)
    }

    @TestCase
    func extractLspBodiesHandlesEmptyInput() {
        let bodies = extractLspBodies("")
        @Expect(bodies.size, 0)
    }

    // ── findLspResponseById 测试 ────────────────────

    @TestCase
    func findLspResponseByIdFindsMatchingResponse() {
        let bodies = [
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}",
            "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"data\":\"test\"}}"
        ]
        let found = findLspResponseById(bodies, 2)
        match (found) {
            case Some((body, _)) =>
                @Expect(body.contains("\"data\":\"test\""))
            case None =>
                @Expect(false)
        }
    }

    @TestCase
    func findLspResponseByIdReturnsNoneForNoMatch() {
        let bodies = ["{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}"]
        let found = findLspResponseById(bodies, 99)
        match (found) {
            case Some(_) => @Expect(false)
            case None => @Expect(true)
        }
    }

    @TestCase
    func findLspResponseByIdSkipsMalformedJson() {
        let bodies = ["not json", "{\"jsonrpc\":\"2.0\",\"id\":5,\"result\":{}}"]
        let found = findLspResponseById(bodies, 5)
        match (found) {
            case Some((body, _)) =>
                @Expect(body.contains("\"id\":5"))
            case None =>
                @Expect(false)
        }
    }

    // ── lspResultToJsonValue 测试 ───────────────────

    @TestCase
    func lspResultToJsonValueParsesValidJson() {
        let result = lspResultToJsonValue("{\"key\":\"value\"}")
        @Expect(result.toString().contains("key"))
    }

    @TestCase
    func lspResultToJsonValueReturnsNullForEmpty() {
        let result = lspResultToJsonValue("")
        @Expect(result.toString(), "null")
    }

    @TestCase
    func lspResultToJsonValueWrapsInvalidAsString() {
        let result = lspResultToJsonValue("not json at all")
        @Expect(result.toString().contains("not json at all"))
    }

    // ── classifyLspResponse 测试 ────────────────────

    @TestCase
    func classifyLspResponseDetectsError() {
        let response = JsonObject()
        let error = JsonObject()
        error.put("code", JsonInt(-32600))
        error.put("message", JsonString("Invalid request"))
        response.put("error", error)
        let result = classifyLspResponse("/bin/lsp", "test/method",
            response.toString(), response)
        @Expect(!result.success)
        @Expect(result.summary.contains("error"))
    }

    @TestCase
    func classifyLspResponseDetectsSuccess() {
        let response = JsonObject()
        let resultData = JsonObject()
        resultData.put("data", JsonString("symbols"))
        response.put("result", resultData)
        let result = classifyLspResponse("/bin/lsp", "test/method",
            response.toString(), response)
        @Expect(result.success)
        @Expect(result.summary.contains("succeeded"))
    }

    @TestCase
    func classifyLspResponseDetectsEmptyResult() {
        let response = JsonObject()
        response.put("result", JsonNull())
        let result = classifyLspResponse("/bin/lsp", "test/method",
            response.toString(), response)
        @Expect(result.success)
        @Expect(result.summary.contains("no symbol payload"))
    }

    // ── buildLspInitializeParams 测试 ───────────────

    @TestCase
    func buildLspInitializeParamsIncludesClientInfo() {
        let params = buildLspInitializeParams()
        let json = params.toString()
        @Expect(json.contains("\"CangjieCoder\""))
        @Expect(json.contains("processId"))
    }

    @TestCase
    func buildLspInitializeParamsIncludesRepoRoot() {
        let tempDir = Directory.createTemp(getTempDirectory())
        try {
            let params = buildLspInitializeParams(repoRoot: tempDir.toString())
            let json = params.toString()
            @Expect(json.contains("rootUri"))
            @Expect(json.contains("workspaceFolders"))
        } finally {
            removeIfExists(tempDir.toString(), recursive: true)
        }
    }

    // ── fileUri 测试 ────────────────────────────────

    @TestCase
    func fileUriStartsWithScheme() {
        let tempDir = Directory.createTemp(getTempDirectory())
        try {
            let uri = fileUri(tempDir.toString())
            @Expect(uri.startsWith("file://"))
        } finally {
            removeIfExists(tempDir.toString(), recursive: true)
        }
    }
}

@Test
class McpProtocolExtendedTest {
    // ── buildToolDefinitions 测试 ───────────────────

    @TestCase
    func buildToolDefinitionsReturns22Tools() {
        // 应注册恰好 22 个工具
        let defs = buildToolDefinitions()
        @Expect(defs.size, 22)
    }

    @TestCase
    func buildToolDefinitionsToolNamesAreUnique() {
        // 所有工具名称应唯一
        let defs = buildToolDefinitions()
        let names = HashMap<String, Bool>()
        for (tool in defs) {
            @Expect(!names.contains(tool.name))
            names[tool.name] = true
        }
    }

    @TestCase
    func buildToolDefinitionsAllHaveDescriptions() {
        // 所有工具应有非空描述
        let defs = buildToolDefinitions()
        for (tool in defs) {
            @Expect(!tool.description.isEmpty())
        }
    }

    @TestCase
    func buildToolDefinitionsRequiredArgsMarked() {
        // workspace.read_file 的 path 参数应标记为必填
        let defs = buildToolDefinitions()
        var found = false
        for (tool in defs) {
            if (tool.name == "workspace.read_file") {
                @Expect(tool.args.size, 1)
                @Expect(tool.args[0].name, "path")
                @Expect(tool.args[0].required)
                found = true
            }
        }
        @Expect(found)
    }

    // ── toolDefinitionsJson 测试 ────────────────────

    @TestCase
    func toolDefinitionsJsonIncludesInputSchema() {
        let json = toolDefinitionsJson()
        @Expect(json.contains("\"inputSchema\""))
        @Expect(json.contains("\"properties\""))
        @Expect(json.contains("\"required\""))
    }

    // ── jsonRpcResult / jsonRpcError 测试 ───────────

    @TestCase
    func jsonRpcResultFormatsCorrectly() {
        let result = jsonRpcResult("1", "{\"pong\":true}")
        @Expect(result.contains("\"jsonrpc\":\"2.0\""))
        @Expect(result.contains("\"id\":1"))
        @Expect(result.contains("\"result\""))
        @Expect(result.contains("\"pong\":true"))
    }

    @TestCase
    func jsonRpcErrorFormatsCorrectly() {
        let result = jsonRpcError("2", -32601, "Method not found")
        @Expect(result.contains("\"jsonrpc\":\"2.0\""))
        @Expect(result.contains("\"id\":2"))
        @Expect(result.contains("\"error\""))
        @Expect(result.contains("-32601"))
        @Expect(result.contains("Method not found"))
    }

    // ── mcpToolCallResultJson 测试 ──────────────────

    @TestCase
    func mcpToolCallResultJsonMarksSuccess() {
        let content = "{\"ok\":true,\"summary\":\"done\",\"data\":{}}"
        let result = mcpToolCallResultJson(content)
        @Expect(result.contains("\"isError\":false"))
        @Expect(result.contains("\"content\""))
        @Expect(result.contains("\"structuredContent\""))
    }

    @TestCase
    func mcpToolCallResultJsonMarksError() {
        let content = "{\"ok\":false,\"summary\":\"failed\",\"data\":{}}"
        let result = mcpToolCallResultJson(content)
        @Expect(result.contains("\"isError\":true"))
    }

    // ── encodeMcpFrame 测试 ─────────────────────────

    @TestCase
    func encodeMcpFrameIncludesContentLength() {
        let body = "{\"test\":true}"
        let frame = encodeMcpFrame(body)
        @Expect(frame.contains("Content-Length:"))
        @Expect(frame.contains(body))
    }

    @TestCase
    func encodeMcpFrameCalculatesCorrectLength() {
        let body = "{}"
        let frame = encodeMcpFrame(body)
        // body "{}" 的字节长度为 2
        @Expect(frame.startsWith("Content-Length: 2"))
    }
}

@Test
class McpHandlersExtendedTest {
    // ── MCP 运行时 handleRequest 通知处理测试 ──────

    @TestCase
    func runtimeIgnoresNotification() {
        // 无 id 的通知请求不应产生响应
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\",\"params\":{}}")
        match (response) {
            case Some(_) => @Expect(false)
            case None => @Expect(true)
        }
    }

    @TestCase
    func runtimeHandlesMultipleSequentialRequests() {
        // 运行时应能处理连续多个请求
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let r1 = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"params\":{}}")
        let r2 = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\",\"params\":{}}")
        match (r1) {
            case Some(p1) =>
                @Expect(p1.contains("\"id\":1"))
                @Expect(p1.contains("\"pong\":true"))
            case None => @Expect(false)
        }
        match (r2) {
            case Some(p2) =>
                @Expect(p2.contains("\"id\":2"))
                @Expect(p2.contains("\"pong\":true"))
            case None => @Expect(false)
        }
    }

    @TestCase
    func runtimeInitializeIncludesVersion() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains("\"version\""))
                @Expect(payload.contains(APP_VERSION))
            case None =>
                @Expect(false)
        }
    }
}
