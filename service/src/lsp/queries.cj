// LSP 查询层：高层查询接口、冷启动回退、探测
package cangjiecoder.lsp

import std.collection.*
import std.fs.*
import std.process.*
import stdx.encoding.json.*

// 构造 LSP initialize 请求的参数对象
public func buildLspInitializeParams(repoRoot!: ?String = None): JsonObject {
    let params = JsonObject()
    params.put("processId", JsonNull())
    let clientInfo = JsonObject()
    clientInfo.put("name", JsonString("CangjieCoder"))
    clientInfo.put("version", JsonString(LSP_APP_VERSION))
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
public func runLspSession(command: String, repoRoot: String, messages: Array<String>): (Array<String>, String) {
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

// 冷启动 LSP 请求：每次查询启动新进程，持久化会话失败时的兜底方案
public func runLspRequestColdStart(repoRoot: String,
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
                    lspShortPreview(fallbackPreview, maxLines: 12), JSON_NULL_LITERAL)
        }
    } catch (e: Exception) {
        return LspQueryResult(true, false, command, method,
            "LSP request failed.",
            lspShortPreview(e.toString(), maxLines: 12), JSON_NULL_LITERAL)
    }
}

// LSP 请求入口：优先通过长驻会话查询以避免冷启动开销，
// 持久化会话失败时自动回退到冷启动模式保证可用性。
public func runLspRequest(repoRoot: String,
                   method: String,
                   params: JsonValue,
                   setupNotifications!: Array<String> = []): LspQueryResult {
    let persistentResult = globalLspSession.query(repoRoot, method, params, setupNotifications: setupNotifications)
    if (persistentResult.success) {
        return persistentResult
    }
    return runLspRequestColdStart(repoRoot, method, params, setupNotifications: setupNotifications)
}

public func queryLspDocumentSymbols(repoRoot: String, path: String): LspQueryResult {
    let fullPath = lspEnsureWorkspacePath(repoRoot, path)
    let params = JsonObject()
    let textDocument = JsonObject()
    textDocument.put("uri", JsonString(fileUri(fullPath)))
    params.put("textDocument", textDocument)
    return runLspRequest(repoRoot,
        "textDocument/documentSymbol",
        params,
        setupNotifications: [buildDidOpenNotification(fullPath)])
}

public func queryLspWorkspaceSymbols(repoRoot: String, query: String): LspQueryResult {
    let params = JsonObject()
    params.put("query", JsonString(query))
    return runLspRequest(repoRoot, "workspace/symbol", params)
}

public func queryLspDefinition(repoRoot: String, path: String, line: Int64, column: Int64): LspQueryResult {
    let fullPath = lspEnsureWorkspacePath(repoRoot, path)
    return runLspRequest(repoRoot,
        "textDocument/definition",
        buildTextDocumentPositionParams(fullPath, line, column),
        setupNotifications: [buildDidOpenNotification(fullPath)])
}

// 判断 LSP 响应是否包含有效的 initialize 结果
func isSuccessfulInitializeResponse(body: String): Bool {
    return body.contains("\"capabilities\"") ||
        (body.contains("\"result\"") && !body.contains("\"error\""))
}

// 在 LSP 响应列表中查找成功的 initialize 应答
func findSuccessfulProbeResponse(bodies: Array<String>): ?String {
    for (body in bodies) {
        if (isSuccessfulInitializeResponse(body)) {
            return body
        }
    }
    return None
}

// LSP 探测：仅执行 initialize → shutdown 以验证 LSP 二进制是否可启动
public func probeLspServer(repoRoot: String): LspProbeResult {
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
        match (findSuccessfulProbeResponse(bodies)) {
            case Some(body) =>
                return LspProbeResult(true, true, command,
                    "LSP initialize probe succeeded.", lspShortPreview(body, maxLines: 12))
            case None => ()
        }
        if (!bodies.isEmpty()) {
            return LspProbeResult(true, false, command,
                "LSP probe returned JSON-RPC responses, but initialize did not succeed cleanly.",
                lspShortPreview(bodies[0], maxLines: 12))
        }
        return LspProbeResult(true, false, command,
            "LSP probe produced no parseable JSON-RPC response.",
            lspShortPreview(stderr, maxLines: 12))
    } catch (e: Exception) {
        return LspProbeResult(true, false, command,
            "LSP probe failed.", lspShortPreview(e.toString(), maxLines: 12))
    }
}

public func buildDidOpenNotification(path: String): String {
    let textDocument = JsonObject()
    textDocument.put("uri", JsonString(fileUri(path)))
    textDocument.put("languageId", JsonString("cangjie"))
    textDocument.put("version", JsonInt(1))
    textDocument.put("text", JsonString(lspReadTextFile(path)))
    let params = JsonObject()
    params.put("textDocument", textDocument)
    return buildLspNotification("textDocument/didOpen", params)
}

public func buildTextDocumentPositionParams(fullPath: String, line: Int64, column: Int64): JsonObject {
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

// 子包内部的文件读取和路径解析（避免对根包的循环依赖）
func lspReadTextFile(path: String): String {
    return String.fromUtf8(File.readFrom(path))
}

func lspEnsureWorkspacePath(repoRoot: String, path: String): String {
    let canonicalRoot = canonicalize(repoRoot).toString()
    let fullPath = if (path.startsWith("/")) { path } else { "${repoRoot}/${path}" }
    if (!exists(fullPath)) {
        throw IllegalArgumentException("Path does not exist: ${path}")
    }
    let canonicalPath = canonicalize(fullPath).toString()
    if (!canonicalPath.startsWith(canonicalRoot)) {
        throw IllegalArgumentException("Path escapes repository root: ${path}")
    }
    return canonicalPath
}
