// LSP 会话管理：命令发现、持久化连接、帧读写
package cangjiecoder.lsp

import std.collection.*
import std.convert.*
import std.env.*
import std.fs.*
import std.io.*
import std.process.*
import stdx.encoding.json.*

// 缓存已解析的 LSP 命令路径，避免每次查询都重复探测文件系统和 PATH。
var lspCommandCache = HashMap<String, String>()

// 按优先级尝试发现可用的 LSP 命令：缓存 → 环境变量 → SDK 自带 → PATH 搜索
public func resolveLspCommand(repoRoot: String): ?String {
    match (lspCommandCache.get(repoRoot)) {
        case Some(cached) => return cached
        case None => ()
    }

    let configuredLspCommand = (getVariable("CANGJIE_LSP_COMMAND") ?? "").trimAscii()
    if (!configuredLspCommand.isEmpty()) {
        lspCommandCache[repoRoot] = configuredLspCommand
        return configuredLspCommand
    }

    let sdkHome = (getVariable("CANGJIE_SDK_HOME") ?? "").trimAscii()
    if (!sdkHome.isEmpty()) {
        let bundledLspPath = "${sdkHome}/tools/bin/LSPServer"
        if (exists(bundledLspPath)) {
            lspCommandCache[repoRoot] = bundledLspPath
            return bundledLspPath
        }
    }

    let (ok, stdout, _) = lspRunCommand("bash", ["-lc", "command -v LSPServer"], repoRoot)
    if (ok) {
        let resolved = stdout.trimAscii()
        if (!resolved.isEmpty()) {
            lspCommandCache[repoRoot] = resolved
            return resolved
        }
    }
    return None
}

// 清除 LSP 命令缓存，在环境变量变更或测试场景下使用
public func clearLspCommandCache(): Unit {
    lspCommandCache = HashMap<String, String>()
}

public func inspectLspStatus(repoRoot: String): LspStatus {
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

// 从输入流中逐字节读取一个 LSP Content-Length 帧。
// 先逐字节读取头部直到 \r\n\r\n 分隔符，解析 Content-Length 后精确读取 body。
public func readLspFrameFromStream(input: InputStream): ?String {
    let headerBytes = ArrayList<Byte>()
    while (true) {
        let buf = Array<Byte>(1, repeat: 0)
        let bytesRead = input.read(buf)
        if (bytesRead <= 0) {
            return None
        }
        headerBytes.add(buf[0])
        let size = headerBytes.size
        if (size >= 4) {
            let tail = Array<Byte>(4, repeat: 0)
            tail[0] = headerBytes[size - 4]
            tail[1] = headerBytes[size - 3]
            tail[2] = headerBytes[size - 2]
            tail[3] = headerBytes[size - 1]
            if (String.fromUtf8(tail) == LSP_HEADER_DELIMITER) {
                break
            }
        }
    }
    let headerStr = String.fromUtf8(headerBytes.toArray())
    var contentLength: Int64 = -1
    for (line in headerStr.lines()) {
        let trimmed = line.trimAscii()
        if (trimmed.startsWith(LSP_CONTENT_LENGTH_HEADER)) {
            try {
                contentLength = Int64.parse(trimmed[LSP_CONTENT_LENGTH_HEADER.size..trimmed.size].trimAscii())
            } catch (_: Exception) {
                return None
            }
        }
    }
    if (contentLength <= 0) {
        return None
    }
    let bodyBuf = Array<Byte>(contentLength, repeat: 0)
    var offset: Int64 = 0
    while (offset < contentLength) {
        let remaining = contentLength - offset
        let chunkSize = if (remaining < LSP_BODY_READ_BUFFER_SIZE) { remaining } else { LSP_BODY_READ_BUFFER_SIZE }
        let chunk = Array<Byte>(chunkSize, repeat: 0)
        let bytesRead = input.read(chunk)
        if (bytesRead <= 0) {
            return None
        }
        var i: Int64 = 0
        while (i < bytesRead) {
            bodyBuf[offset + i] = chunk[i]
            i += 1
        }
        offset += bytesRead
    }
    return String.fromUtf8(bodyBuf)
}

// LspSessionManager 维护一个长驻 LSP 子进程，
// 首次查询时执行 initialize 握手，后续查询复用已初始化的进程，
// 避免每次都冷启动 LSP Server 带来的高延迟和 CPU 消耗。
public class LspSessionManager {
    var process: ?SubProcess = None
    var command: String = ""
    var repoRoot: String = ""
    var initialized: Bool = false
    var nextRequestId: Int64 = 10

    func sendFrame(message: String): Unit {
        match (process) {
            case Some(proc) =>
                proc.stdInPipe.write(encodeLspFrame(message).toArray())
                proc.stdInPipe.flush()
            case None =>
                throw IllegalArgumentException("LSP process not started")
        }
    }

    func receiveFrame(): ?String {
        match (process) {
            case Some(proc) => return readLspFrameFromStream(proc.stdOutPipe)
            case None => return None
        }
    }

    func isResponseWithId(frame: String, targetId: Int64): Bool {
        try {
            let obj = JsonValue.fromStr(frame).asObject()
            match (obj.get("id")) {
                case Some(idValue) => return idValue.toString() == "${targetId}"
                case None => return false
            }
        } catch (_: Exception) {
            return false
        }
    }

    func ensureInitialized(targetRepoRoot: String): Bool {
        if (initialized && repoRoot == targetRepoRoot) {
            return true
        }
        close()
        let cmd = match (resolveLspCommand(targetRepoRoot)) {
            case Some(c) => c
            case None => return false
        }
        try {
            let proc = launch(cmd, [],
                workingDirectory: Path(targetRepoRoot),
                stdIn: ProcessRedirect.Pipe,
                stdOut: ProcessRedirect.Pipe,
                stdErr: ProcessRedirect.Pipe)
            process = proc
            command = cmd
            repoRoot = targetRepoRoot
            sendFrame(buildLspRequest(1, "initialize", buildLspInitializeParams(repoRoot: targetRepoRoot)))
            var found = false
            var attempts: Int64 = 0
            while (attempts < LSP_MAX_INITIALIZE_ATTEMPTS && !found) {
                match (receiveFrame()) {
                    case Some(frame) =>
                        if (isResponseWithId(frame, 1)) {
                            found = true
                        }
                    case None => break
                }
                attempts += 1
            }
            if (!found) {
                close()
                return false
            }
            sendFrame(buildLspNotification("initialized", JsonObject()))
            initialized = true
            return true
        } catch (_: Exception) {
            close()
            return false
        }
    }

    // 通过长驻进程发送 LSP 请求并读取对应响应
    public func query(targetRepoRoot: String,
                      method: String,
                      params: JsonValue,
                      setupNotifications!: Array<String> = []): LspQueryResult {
        if (!ensureInitialized(targetRepoRoot)) {
            return LspQueryResult(false, false, "", method,
                "Failed to initialize persistent LSP session.", "", JSON_NULL_LITERAL)
        }
        try {
            let requestId = nextRequestId
            nextRequestId += 1
            for (notification in setupNotifications) {
                sendFrame(notification)
            }
            sendFrame(buildLspRequest(requestId, method, params))
            var attempts: Int64 = 0
            while (attempts < LSP_MAX_QUERY_ATTEMPTS) {
                match (receiveFrame()) {
                    case Some(frame) =>
                        if (isResponseWithId(frame, requestId)) {
                            try {
                                let response = JsonValue.fromStr(frame).asObject()
                                return classifyLspResponse(command, method, frame, response)
                            } catch (_: Exception) {
                                return LspQueryResult(true, false, command, method,
                                    "Failed to parse LSP response.", "", JSON_NULL_LITERAL)
                            }
                        }
                    case None =>
                        initialized = false
                        return LspQueryResult(true, false, command, method,
                            "LSP persistent session stream ended unexpectedly.", "", JSON_NULL_LITERAL)
                }
                attempts += 1
            }
            return LspQueryResult(true, false, command, method,
                "Timed out waiting for LSP response.", "", JSON_NULL_LITERAL)
        } catch (e: Exception) {
            initialized = false
            return LspQueryResult(true, false, command, method,
                "LSP persistent session failed.",
                lspShortPreview(e.toString(), maxLines: 12), JSON_NULL_LITERAL)
        }
    }

    // 关闭 LSP 子进程，发送 shutdown/exit 协议消息后强制终止
    public func close(): Unit {
        if (initialized) {
            try {
                sendFrame(buildLspRequest(nextRequestId, "shutdown", JsonNull()))
                nextRequestId += 1
                sendFrame(buildLspNotification("exit", JsonNull()))
            } catch (_: Exception) {
                // 关闭时忽略发送错误
            }
        }
        match (process) {
            case Some(proc) =>
                try { proc.terminate(force: true) } catch (_: Exception) {}
            case None => ()
        }
        process = None
        initialized = false
    }
}

// 全局 LSP 会话管理器，被所有 LSP 查询复用
public var globalLspSession = LspSessionManager()

// 关闭全局 LSP 会话
public func closeLspSession(): Unit {
    globalLspSession.close()
}

// 子包内部使用的命令执行（避免对根包的循环依赖）
func lspRunCommand(command: String, arguments: Array<String>, workingDirectory: String): (Bool, String, String) {
    try {
        let (status, stdoutBytes, stderrBytes) = launch(command, arguments,
            workingDirectory: Path(workingDirectory),
            stdIn: ProcessRedirect.Pipe,
            stdOut: ProcessRedirect.Pipe,
            stdErr: ProcessRedirect.Pipe).waitOutput()
        return (status == 0, String.fromUtf8(stdoutBytes), String.fromUtf8(stderrBytes))
    } catch (e: Exception) {
        return (false, "", e.toString())
    }
}
