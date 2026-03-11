// LSP 查询层：高层查询接口、冷启动回退、探测
// 提供面向上层调用者的 LSP 查询 API，内部优先使用持久化会话，
// 失败时自动回退到冷启动模式（每次查询启动新进程），确保查询可用性。
package cangjiecoder.lsp

import std.collection.*
import std.fs.*
import std.process.*
import stdx.encoding.json.*

// ── LSP 会话运行 ─────────────────────────────────────

// 构造 LSP initialize 请求的参数对象
public func buildLspInitializeParams(repoRoot!: ?String = None): JsonObject {
    let params = JsonObject()
    params.put("processId", JsonNull())

    // 客户端标识信息
    let clientInfo = JsonObject()
    clientInfo.put("name", JsonString("CangjieCoder"))
    clientInfo.put("version", JsonString(LSP_APP_VERSION))
    params.put("clientInfo", clientInfo)

    // 设置工作区根目录和工作区文件夹
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

// 将多个 LSP JSON-RPC 消息编码成帧序列，写入进程 stdin 后读取全部 stdout/stderr。
// 注意: 此函数在某些 LSP 实现中可能因 stdin 关闭导致响应丢失（参见 issue.md 问题 5）。
// 主查询路径应优先使用 globalLspSession 持久化会话。
// 返回 (解析后的 JSON body 数组, 标准错误输出)。
public func runLspSession(command: String, repoRoot: String, messages: Array<String>): (Array<String>, String) {
    let process = launch(command,
        [],
        workingDirectory: Path(repoRoot),
        stdIn: ProcessRedirect.Pipe,
        stdOut: ProcessRedirect.Pipe,
        stdErr: ProcessRedirect.Pipe)

    // 将所有消息编码为帧并写入子进程 stdin
    let payload = ArrayList<String>()
    for (message in messages) {
        payload.add(encodeLspFrame(message))
    }
    process.stdInPipe.write(String.join(payload.toArray(), delimiter: "").toArray())
    process.stdInPipe.flush()

    // 等待进程结束并收集输出
    let (_, stdoutBytes, stderrBytes) = process.waitOutput()
    let stdout = String.fromUtf8(stdoutBytes)
    let stderr = String.fromUtf8(stderrBytes)
    return (extractLspBodies(stdout), stderr)
}

// ── 冷启动查询 ───────────────────────────────────────

// 冷启动 LSP 请求：每次查询启动新进程（initialize → 查询 → shutdown），
// 作为持久化会话失败时的兜底方案，保证查询可用性。
public func runLspRequestColdStart(repoRoot: String,
                   method: String,
                   params: JsonValue,
                   setupNotifications!: Array<String> = []): LspQueryResult {
    if (let Some(command) <- resolveLspCommand(repoRoot)) {
        try {
            // 构建完整的 LSP 消息序列：initialize → initialized → [didOpen] → query → shutdown → exit
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
            // 在响应中查找与请求 id 匹配的应答
            if (let Some((body, response)) <- findLspResponseById(bodies, requestId)) {
                return classifyLspResponse(command, method, body, response)
            }
            let fallbackPreview = if (stderr.trimAscii().isEmpty()) {
                String.join(bodies, delimiter: "\n")
            } else {
                stderr
            }
            return LspQueryResult(true, false, command, method,
                "LSP request produced no parseable response for the requested method.",
                lspShortPreview(fallbackPreview, maxLines: 12), JSON_NULL_LITERAL)
        } catch (e: Exception) {
            return LspQueryResult(true, false, command, method,
                "LSP request failed.",
                lspShortPreview(e.toString(), maxLines: 12), JSON_NULL_LITERAL)
        }
    }
    return LspQueryResult(false, false, "", method,
        "No Cangjie LSP binary was detected for this request.", "", JSON_NULL_LITERAL)
}

// ── 主查询入口 ───────────────────────────────────────

// LSP 请求入口：优先通过长驻会话查询以避免冷启动开销，
// 持久化会话失败时自动回退到冷启动模式保证可用性。
public func runLspRequest(repoRoot: String,
                   method: String,
                   params: JsonValue,
                   setupNotifications!: Array<String> = []): LspQueryResult {
    // 优先尝试持久化会话
    let persistentResult = globalLspSession.query(repoRoot, method, params, setupNotifications: setupNotifications)
    if (persistentResult.success) {
        return persistentResult
    }
    // 持久化失败，回退到冷启动
    return runLspRequestColdStart(repoRoot, method, params, setupNotifications: setupNotifications)
}

// ── 具体查询方法 ─────────────────────────────────────

// 查询指定文件的文档符号（函数、类、变量等声明）
public func queryLspDocumentSymbols(repoRoot: String, path: String): LspQueryResult {
    if (let Some(fullPath) <- lspEnsureWorkspacePath(repoRoot, path)) {
        let params = JsonObject()
        let textDocument = JsonObject()
        textDocument.put("uri", JsonString(fileUri(fullPath)))
        params.put("textDocument", textDocument)
        return runLspRequest(repoRoot,
            "textDocument/documentSymbol",
            params,
            setupNotifications: [buildDidOpenNotification(fullPath)])
    }
    return LspQueryResult(false, false, "", "textDocument/documentSymbol",
        "Path does not exist or escapes repository root: ${path}", "", JSON_NULL_LITERAL)
}

// 查询工作区范围内匹配指定关键字的符号
public func queryLspWorkspaceSymbols(repoRoot: String, query: String): LspQueryResult {
    let params = JsonObject()
    params.put("query", JsonString(query))
    return runLspRequest(repoRoot, "workspace/symbol", params)
}

// 查询指定位置的符号定义（跳转到定义）
public func queryLspDefinition(repoRoot: String, path: String, line: Int64, column: Int64): LspQueryResult {
    if (let Some(fullPath) <- lspEnsureWorkspacePath(repoRoot, path)) {
        return runLspRequest(repoRoot,
            "textDocument/definition",
            buildTextDocumentPositionParams(fullPath, line, column),
            setupNotifications: [buildDidOpenNotification(fullPath)])
    }
    return LspQueryResult(false, false, "", "textDocument/definition",
        "Path does not exist or escapes repository root: ${path}", "", JSON_NULL_LITERAL)
}

// ── LSP 探测 ─────────────────────────────────────────

// LSP 探测：通过持久化会话管理器执行 initialize 握手，
// 验证 LSP 二进制是否可正常启动和通信。
public func probeLspServer(repoRoot: String): LspProbeResult {
    if (let Some(command) <- resolveLspCommand(repoRoot)) {
        // 使用持久化会话管理器尝试初始化，它内部已实现交互式帧读写
        if (globalLspSession.ensureInitialized(repoRoot)) {
            return LspProbeResult(true, true, command,
                "LSP initialize probe succeeded.", "Session initialized successfully.")
        }
        return LspProbeResult(true, false, command,
            "LSP probe: binary found but initialize handshake did not succeed.", "")
    }
    return LspProbeResult(false, false, "", "No Cangjie LSP binary was detected for probing.", "")
}

// ── LSP 消息构建辅助 ─────────────────────────────────

// 构建 textDocument/didOpen 通知，用于在查询前告知 LSP 服务器文件内容
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

// 构建 textDocument/definition 等请求所需的位置参数（文档 URI + 行列坐标）
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

// ── 子包内部工具函数（避免对根包循环依赖） ───────────

// 子包内部的文件读取
func lspReadTextFile(path: String): String {
    return String.fromUtf8(File.readFrom(path))
}

// 子包内部的工作区路径安全校验，返回 None 表示路径不存在或逃逸了工作区根目录
func lspEnsureWorkspacePath(repoRoot: String, path: String): ?String {
    let canonicalRoot = canonicalize(repoRoot).toString()
    let fullPath = if (path.startsWith("/")) { path } else { "${repoRoot}/${path}" }
    if (!exists(fullPath)) {
        return None
    }
    let canonicalPath = canonicalize(fullPath).toString()
    if (!canonicalPath.startsWith(canonicalRoot)) {
        return None
    }
    return canonicalPath
}
