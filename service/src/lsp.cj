package cangjiecoder

import std.collection.*
import std.convert.*
import std.env.*
import std.fs.*
import std.io.*
import std.process.*
import stdx.encoding.json.*

// LSP 协议常量
const LSP_HEADER_DELIMITER: String = "\r\n\r\n"
const LSP_CONTENT_LENGTH_HEADER: String = "Content-Length:"
const JSON_NULL_LITERAL: String = "null"
const JSON_EMPTY_ARRAY_LITERAL: String = "[]"
const JSON_EMPTY_OBJECT_LITERAL: String = "{}"

struct LspStatus {
    public LspStatus(let available: Bool,
                     let command: String,
                     let summary: String,
                     let sourceHint: String) {}
}

struct LspProbeResult {
    public LspProbeResult(let available: Bool,
                          let success: Bool,
                          let command: String,
                          let summary: String,
                          let responsePreview: String) {}
}

struct LspQueryResult {
    public LspQueryResult(let available: Bool,
                          let success: Bool,
                          let command: String,
                          let method: String,
                          let summary: String,
                          let responsePreview: String,
                          let resultJson: String) {}
}

// 按优先级尝试发现可用的 LSP 命令：环境变量 → SDK 自带 → PATH 搜索
func resolveLspCommand(repoRoot: String): ?String {
    let configuredLspCommand = (getVariable("CANGJIE_LSP_COMMAND") ?? "").trimAscii()
    if (!configuredLspCommand.isEmpty()) {
        return configuredLspCommand
    }

    let sdkHome = (getVariable("CANGJIE_SDK_HOME") ?? "").trimAscii()
    if (!sdkHome.isEmpty()) {
        let bundledLspPath = "${sdkHome}/tools/bin/LSPServer"
        if (exists(bundledLspPath)) {
            return bundledLspPath
        }
    }

    let (ok, stdout, _) = runCommandWithCapturedOutput("bash", ["-lc", "command -v LSPServer"], repoRoot)
    if (ok) {
        let resolved = stdout.trimAscii()
        if (!resolved.isEmpty()) {
            return resolved
        }
    }
    return None
}

func inspectLspStatus(repoRoot: String): LspStatus {
    match (resolveLspCommand(repoRoot)) {
        case Some(command) =>
            return LspStatus(
                true,
                command,
                "Detected a Cangjie LSP binary. You can wire it into future symbol/hover/diagnostic sessions via CANGJIE_LSP_COMMAND.",
                "SDK 1.0.5 ships LSPServer under tools/bin, and the tools-source package can be used for deeper protocol integration."
            )
        case None =>
            return LspStatus(
                false,
                "",
                "No Cangjie LSP binary was detected. Configure CANGJIE_LSP_COMMAND or CANGJIE_SDK_HOME to enable stronger analysis hooks.",
                "Use the 1.0.5 SDK release or the tools-source package to provide LSPServer."
            )
    }
}

// 将 JSON 消息体编码为 LSP Content-Length 帧
func encodeLspFrame(body: String): String {
    return "${LSP_CONTENT_LENGTH_HEADER} ${body.toArray().size}${LSP_HEADER_DELIMITER}${body}"
}

func buildLspRequest(id: Int64, method: String, params: JsonValue): String {
    let root = JsonObject()
    root.put("jsonrpc", JsonString("2.0"))
    root.put("id", JsonInt(id))
    root.put("method", JsonString(method))
    root.put("params", params)
    return root.toString()
}

func buildLspNotification(method: String, params: JsonValue): String {
    let root = JsonObject()
    root.put("jsonrpc", JsonString("2.0"))
    root.put("method", JsonString(method))
    root.put("params", params)
    return root.toString()
}

// 从 LSP 多帧拼接的原始输出中解析出各个 JSON body
func extractLspBodies(raw: String): Array<String> {
    let bodies = ArrayList<String>()
    var offset: Int64 = 0
    while (offset < raw.size) {
        let headerEnd = match (raw.indexOf(LSP_HEADER_DELIMITER, offset)) {
            case Some(value) => value
            case None => break
        }
        let headers = raw[offset..headerEnd]
        let lengthStart = match (headers.indexOf(LSP_CONTENT_LENGTH_HEADER)) {
            case Some(value) => value + LSP_CONTENT_LENGTH_HEADER.size
            case None => break
        }
        let lengthLineEnd = match (headers.indexOf("\r\n", lengthStart)) {
            case Some(value) => value
            case None => headers.size
        }
        let length = Int64.parse(headers[lengthStart..lengthLineEnd].trimAscii())
        let bodyStart = headerEnd + LSP_HEADER_DELIMITER.size
        let bodyEnd = bodyStart + length
        if (bodyEnd > raw.size) {
            break
        }
        bodies.add(raw[bodyStart..bodyEnd])
        offset = bodyEnd
    }
    return bodies.toArray()
}

// 将文件系统路径转为 file:// URI，转义特殊字符
func fileUri(path: String): String {
    let canonicalPath = canonicalize(path).toString()
    let encodedPath = canonicalPath
        .replace("%", "%25")
        .replace(" ", "%20")
        .replace("#", "%23")
        .replace("?", "%3F")
    return "file://${encodedPath}"
}

func buildDidOpenNotification(path: String): String {
    let textDocument = JsonObject()
    textDocument.put("uri", JsonString(fileUri(path)))
    textDocument.put("languageId", JsonString("cangjie"))
    textDocument.put("version", JsonInt(1))
    textDocument.put("text", JsonString(readTextFile(path)))
    let params = JsonObject()
    params.put("textDocument", textDocument)
    return buildLspNotification("textDocument/didOpen", params)
}

func buildTextDocumentPositionParams(fullPath: String, line: Int64, column: Int64): JsonObject {
    let textDocument = JsonObject()
    textDocument.put("uri", JsonString(fileUri(fullPath)))
    let position = JsonObject()
    position.put("line", JsonInt(line))
    position.put("character", JsonInt(column))
    let params = JsonObject()
    params.put("textDocument", textDocument)
    params.put("position", position)
    return params
}

func lspResultToJsonValue(text: String): JsonValue {
    if (text.trimAscii().isEmpty()) {
        return JsonNull()
    }
    try {
        return JsonValue.fromStr(text)
    } catch (e: Exception) {
        return JsonString(text)
    }
}

// 构造 LSP initialize 请求的参数对象，含 clientInfo、rootUri、workspaceFolders 等
func buildLspInitializeParams(repoRoot!: ?String = None): JsonObject {
    let params = JsonObject()
    params.put("processId", JsonNull())
    let clientInfo = JsonObject()
    clientInfo.put("name", JsonString("CangjieCoder"))
    clientInfo.put("version", JsonString(APP_VERSION))
    params.put("clientInfo", clientInfo)

    match (repoRoot) {
        case Some(root) =>
            params.put("rootUri", JsonString(fileUri(root)))
            let workspaceFolder = JsonObject()
            workspaceFolder.put("uri", JsonString(fileUri(root)))
            workspaceFolder.put("name", JsonString(Path(root).fileName))
            let workspaceFolders = JsonArray()
            workspaceFolders.add(workspaceFolder)
            params.put("workspaceFolders", workspaceFolders)
        case None =>
            params.put("rootUri", JsonNull())
    }

    params.put("capabilities", JsonObject())
    return params
}

// 将多个 LSP JSON-RPC 消息编码成帧序列，写入进程 stdin 后读取全部 stdout/stderr
func runLspSession(command: String, repoRoot: String, messages: Array<String>): (Array<String>, String) {
    let process = launch(command,
        [],
        workingDirectory: Path(repoRoot),
        stdIn: ProcessRedirect.Pipe,
        stdOut: ProcessRedirect.Pipe,
        stdErr: ProcessRedirect.Pipe)
    let payload = ArrayList<String>()
    for (message in messages) {
        payload.add(encodeLspFrame(message))
    }
    process.stdInPipe.write(String.join(payload.toArray(), delimiter: "").toArray())
    process.stdInPipe.flush()
    let (_, stdoutBytes, stderrBytes) = process.waitOutput()
    let stdout = String.fromUtf8(stdoutBytes)
    let stderr = String.fromUtf8(stderrBytes)
    return (extractLspBodies(stdout), stderr)
}

// 在响应体数组中查找指定 id 的 JSON-RPC 应答
func findLspResponseById(bodies: Array<String>, requestId: Int64): ?(String, JsonObject) {
    let idStr = "${requestId}"
    for (body in bodies) {
        try {
            let response = JsonValue.fromStr(body).asObject()
            let responseId = match (response.get("id")) {
                case Some(value) => value.toString()
                case None => ""
            }
            if (responseId == idStr) {
                return (body, response)
            }
        } catch (e: Exception) {
            continue
        }
    }
    return None
}

// 将 JSON-RPC 应答分类为 error/result，返回结构化的 LspQueryResult
func classifyLspResponse(command: String, method: String, body: String, response: JsonObject): LspQueryResult {
    if (let Some(errorValue) <- response.get("error")) {
        return LspQueryResult(true, false, command, method,
            "LSP request returned an error.",
            shortPreview(body, maxLines: 12),
            errorValue.toString())
    }
    if (let Some(resultValue) <- response.get("result")) {
        let resultText = resultValue.toString()
        let summary = if (resultText == JSON_NULL_LITERAL ||
            resultText == JSON_EMPTY_ARRAY_LITERAL ||
            resultText == JSON_EMPTY_OBJECT_LITERAL) {
            "LSP request succeeded, but the server returned no symbol payload."
        } else {
            "LSP request succeeded."
        }
        return LspQueryResult(true, true, command, method,
            summary, shortPreview(body, maxLines: 12), resultText)
    }
    return LspQueryResult(true, false, command, method,
        "LSP response contained neither result nor error.",
        shortPreview(body, maxLines: 12), JSON_NULL_LITERAL)
}

// 完整的 LSP 请求：发现命令 → 启动进程 → 发送 initialize/request/shutdown → 解析响应
func runLspRequest(repoRoot: String,
                   method: String,
                   params: JsonValue,
                   setupNotifications!: Array<String> = []): LspQueryResult {
    let command = match (resolveLspCommand(repoRoot)) {
        case Some(cmd) => cmd
        case None =>
            return LspQueryResult(false, false, "", method,
                "No Cangjie LSP binary was detected for this request.", "", JSON_NULL_LITERAL)
    }

    try {
        let requestId: Int64 = 3
        let messages = ArrayList<String>()
        messages.add(buildLspRequest(1, "initialize", buildLspInitializeParams(repoRoot: repoRoot)))
        messages.add(buildLspNotification("initialized", JsonObject()))
        for (notification in setupNotifications) {
            messages.add(notification)
        }
        messages.add(buildLspRequest(requestId, method, params))
        messages.add(buildLspRequest(4, "shutdown", JsonNull()))
        messages.add(buildLspNotification("exit", JsonNull()))

        let (bodies, stderr) = runLspSession(command, repoRoot, messages.toArray())
        match (findLspResponseById(bodies, requestId)) {
            case Some((body, response)) =>
                return classifyLspResponse(command, method, body, response)
            case None =>
                let fallbackPreview = if (stderr.trimAscii().isEmpty()) {
                    String.join(bodies, delimiter: "\n")
                } else {
                    stderr
                }
                return LspQueryResult(true, false, command, method,
                    "LSP request produced no parseable response for the requested method.",
                    shortPreview(fallbackPreview, maxLines: 12), JSON_NULL_LITERAL)
        }
    } catch (e: Exception) {
        return LspQueryResult(true, false, command, method,
            "LSP request failed.",
            shortPreview(e.toString(), maxLines: 12), JSON_NULL_LITERAL)
    }
}

func queryLspDocumentSymbols(repoRoot: String, path: String): LspQueryResult {
    let fullPath = ensureWorkspacePath(repoRoot, path)
    let params = JsonObject()
    let textDocument = JsonObject()
    textDocument.put("uri", JsonString(fileUri(fullPath)))
    params.put("textDocument", textDocument)
    return runLspRequest(repoRoot,
        "textDocument/documentSymbol",
        params,
        setupNotifications: [buildDidOpenNotification(fullPath)])
}

func queryLspWorkspaceSymbols(repoRoot: String, query: String): LspQueryResult {
    let params = JsonObject()
    params.put("query", JsonString(query))
    return runLspRequest(repoRoot, "workspace/symbol", params)
}

func queryLspDefinition(repoRoot: String, path: String, line: Int64, column: Int64): LspQueryResult {
    let fullPath = ensureWorkspacePath(repoRoot, path)
    return runLspRequest(repoRoot,
        "textDocument/definition",
        buildTextDocumentPositionParams(fullPath, line, column),
        setupNotifications: [buildDidOpenNotification(fullPath)])
}

// LSP 探测：仅执行 initialize → shutdown 以验证 LSP 二进制是否可启动
func probeLspServer(repoRoot: String): LspProbeResult {
    let command = match (resolveLspCommand(repoRoot)) {
        case Some(cmd) => cmd
        case None =>
            return LspProbeResult(false, false, "", "No Cangjie LSP binary was detected for probing.", "")
    }

    try {
        let messages = [
            buildLspRequest(1, "initialize", buildLspInitializeParams()),
            buildLspNotification("initialized", JsonObject()),
            buildLspRequest(2, "shutdown", JsonNull()),
            buildLspNotification("exit", JsonNull())
        ]
        let (bodies, stderr) = runLspSession(command, repoRoot, messages)
        for (body in bodies) {
            if (body.contains("\"capabilities\"") || (body.contains("\"result\"") && !body.contains("\"error\""))) {
                return LspProbeResult(true, true, command,
                    "LSP initialize probe succeeded.", shortPreview(body, maxLines: 12))
            }
        }
        if (!bodies.isEmpty()) {
            return LspProbeResult(true, false, command,
                "LSP probe returned JSON-RPC responses, but initialize did not succeed cleanly.",
                shortPreview(bodies[0], maxLines: 12))
        }
        return LspProbeResult(true, false, command,
            "LSP probe produced no parseable JSON-RPC response.",
            shortPreview(stderr, maxLines: 12))
    } catch (e: Exception) {
        return LspProbeResult(true, false, command,
            "LSP probe failed.", shortPreview(e.toString(), maxLines: 12))
    }
}
