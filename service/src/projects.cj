package cangjiecoder

import std.collection.*
import std.convert.*
import std.env.*
import std.fs.*
import std.io.*
import std.process.*
import stdx.encoding.json.*

const LSP_HEADER_DELIMITER: String = "\r\n\r\n"
const LSP_CONTENT_LENGTH_HEADER: String = "Content-Length:"
const JSON_NULL_LITERAL: String = "null"
const JSON_EMPTY_ARRAY_LITERAL: String = "[]"
const JSON_EMPTY_OBJECT_LITERAL: String = "{}"

struct ExampleProjectSpec {
    public ExampleProjectSpec(let id: String,
                              let name: String,
                              let description: String,
                              let templatePath: String) {}
}

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

func listExampleProjects(serviceRoot: String): Array<ExampleProjectSpec> {
    let examplesRoot = resolveBundledPath(serviceRoot, "examples")
    return [
        ExampleProjectSpec(
            "json_parser",
            "JsonParser example project",
            "Buildable and testable Cangjie JsonParser example project for the first autonomous project workflow.",
            "${examplesRoot}/json_parser"
        )
    ]
}

func findExampleProject(serviceRoot: String, projectId: String): ?ExampleProjectSpec {
    let normalizedId = projectId.toAsciiLower().trimAscii()
    for (project in listExampleProjects(serviceRoot)) {
        if (project.id == normalizedId) {
            return project
        }
    }
    return None
}

func ensurePlannedWorkspacePath(repoRoot: String, path: String): String {
    let canonicalRoot = canonicalize(repoRoot).toString()
    let fullPath = resolveRepoPath(repoRoot, path)
    let plannedPath = Path(fullPath)
    let parentPath = plannedPath.parent
    if (parentPath.toString().isEmpty()) {
        throw IllegalArgumentException("Parent directory does not exist: ${parentPath}")
    }
    var existingParentPath = parentPath
    var existingParent = existingParentPath.toString()
    while (!existingParent.isEmpty() && !exists(existingParent)) {
        existingParentPath = existingParentPath.parent
        existingParent = existingParentPath.toString()
    }
    if (existingParent.isEmpty()) {
        throw IllegalArgumentException("Parent directory does not exist: ${parentPath}")
    }
    // Validate against the nearest existing ancestor so nested new paths such
    // as target/generated/demo can be created safely without precreating every parent.
    let canonicalParent = canonicalize(existingParent).toString()
    if (!canonicalParent.startsWith(canonicalRoot)) {
        throw IllegalArgumentException("Path escapes repository root: ${path}")
    }
    return fullPath
}

func bootstrapJsonParserProject(serviceRoot: String, workspaceRoot: String, destination: String): String {
    let outputPath = ensurePlannedWorkspacePath(workspaceRoot, destination)
    if (exists(outputPath)) {
        return "Destination already exists: ${outputPath}"
    }

    match (findExampleProject(serviceRoot, "json_parser")) {
        case Some(project) =>
            if (!exists(project.templatePath)) {
                return "JsonParser example template is missing: ${project.templatePath}"
            }
            let outputParent = Path(outputPath).parent.toString()
            if (!outputParent.isEmpty() && !exists(outputParent)) {
                Directory.create(ensurePlannedWorkspacePath(workspaceRoot, outputParent), recursive: true)
            }
            copy(project.templatePath, to: outputPath)
            removeIfExists("${outputPath}/target", recursive: true)
            removeIfExists("${outputPath}/cjpm.lock")
            return "Bootstrapped JsonParser example at ${outputPath}"
        case None =>
            return "JsonParser example template is missing"
    }
}

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

func encodeLspFrame(body: String): String {
    // LSP Content-Length is defined in bytes, so UTF-8 byte count is required here.
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

func runLspRequest(repoRoot: String,
                   method: String,
                   params: JsonValue,
                   setupNotifications!: Array<String> = []): LspQueryResult {
    match (resolveLspCommand(repoRoot)) {
        case None =>
            return LspQueryResult(false, false, "", method, "No Cangjie LSP binary was detected for this request.", "", JSON_NULL_LITERAL)
        case Some(command) =>
            try {
                let process = launch(command,
                    [],
                    workingDirectory: Path(repoRoot),
                    stdIn: ProcessRedirect.Pipe,
                    stdOut: ProcessRedirect.Pipe,
                    stdErr: ProcessRedirect.Pipe)
                let initializeParams = JsonObject()
                initializeParams.put("processId", JsonNull())
                let clientInfo = JsonObject()
                clientInfo.put("name", JsonString("CangjieCoder"))
                clientInfo.put("version", JsonString(APP_VERSION))
                initializeParams.put("clientInfo", clientInfo)
                initializeParams.put("rootUri", JsonString(fileUri(repoRoot)))
                let workspaceFolder = JsonObject()
                workspaceFolder.put("uri", JsonString(fileUri(repoRoot)))
                workspaceFolder.put("name", JsonString(Path(repoRoot).fileName))
                let workspaceFolders = JsonArray()
                workspaceFolders.add(workspaceFolder)
                initializeParams.put("workspaceFolders", workspaceFolders)
                initializeParams.put("capabilities", JsonObject())
                let initialize = buildLspRequest(1, "initialize", initializeParams)
                let initialized = buildLspNotification("initialized", JsonObject())
                let requestId: Int64 = 3
                let request = buildLspRequest(requestId, method, params)
                let shutdown = buildLspRequest(4, "shutdown", JsonNull())
                let exitRequest = buildLspNotification("exit", JsonNull())
                let frames = ArrayList<String>()
                frames.add(encodeLspFrame(initialize))
                frames.add(encodeLspFrame(initialized))
                for (notification in setupNotifications) {
                    frames.add(encodeLspFrame(notification))
                }
                frames.add(encodeLspFrame(request))
                frames.add(encodeLspFrame(shutdown))
                frames.add(encodeLspFrame(exitRequest))
                process.stdInPipe.write(String.join(frames.toArray(), delimiter: "").toArray())
                process.stdInPipe.flush()
                let (_, stdoutBytes, stderrBytes) = process.waitOutput()
                let stdout = String.fromUtf8(stdoutBytes)
                let stderr = String.fromUtf8(stderrBytes)
                let bodies = extractLspBodies(stdout)
                for (body in bodies) {
                    try {
                        let response = JsonValue.fromStr(body).asObject()
                        let responseId = match (response.get("id")) {
                            case Some(value) => value.toString()
                            case None => ""
                        }
                        if (responseId != "${requestId}") {
                            continue
                        }
                        if (let Some(errorValue) <- response.get("error")) {
                            return LspQueryResult(true,
                                false,
                                command,
                                method,
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
                            return LspQueryResult(true,
                                true,
                                command,
                                method,
                                summary,
                                shortPreview(body, maxLines: 12),
                                resultText)
                        }
                    } catch (e: Exception) {
                        continue
                    }
                }
                return LspQueryResult(true,
                    false,
                    command,
                    method,
                    "LSP request produced no parseable response for the requested method.",
                    shortPreview(if (stderr.trimAscii().isEmpty()) { stdout } else { stderr }, maxLines: 12),
                    JSON_NULL_LITERAL)
            } catch (e: Exception) {
                return LspQueryResult(true,
                    false,
                    command,
                    method,
                    "LSP request failed.",
                    shortPreview(e.toString(), maxLines: 12),
                    JSON_NULL_LITERAL)
            }
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

func probeLspServer(repoRoot: String): LspProbeResult {
    match (resolveLspCommand(repoRoot)) {
        case None =>
            return LspProbeResult(false, false, "", "No Cangjie LSP binary was detected for probing.", "")
        case Some(command) =>
            try {
                let process = launch(command,
                    [],
                    workingDirectory: Path(repoRoot),
                    stdIn: ProcessRedirect.Pipe,
                    stdOut: ProcessRedirect.Pipe,
                    stdErr: ProcessRedirect.Pipe)
                let initializeParams = JsonObject()
                initializeParams.put("processId", JsonNull())
                let clientInfo = JsonObject()
                clientInfo.put("name", JsonString("CangjieCoder"))
                clientInfo.put("version", JsonString(APP_VERSION))
                initializeParams.put("clientInfo", clientInfo)
                initializeParams.put("rootUri", JsonNull())
                initializeParams.put("capabilities", JsonObject())
                let initialize = buildLspRequest(1, "initialize", initializeParams)
                let initialized = buildLspNotification("initialized", JsonObject())
                let shutdown = buildLspRequest(2, "shutdown", JsonNull())
                let exitRequest = buildLspNotification("exit", JsonNull())
                let payload = "${encodeLspFrame(initialize)}${encodeLspFrame(initialized)}${encodeLspFrame(shutdown)}${encodeLspFrame(exitRequest)}"
                process.stdInPipe.write(payload.toArray())
                process.stdInPipe.flush()
                let (_, stdoutBytes, stderrBytes) = process.waitOutput()
                let stdout = String.fromUtf8(stdoutBytes)
                let stderr = String.fromUtf8(stderrBytes)
                let bodies = extractLspBodies(stdout)
                for (body in bodies) {
                    if (body.contains("\"capabilities\"") || (body.contains("\"result\"") && !body.contains("\"error\""))) {
                        return LspProbeResult(true, true, command, "LSP initialize probe succeeded.", shortPreview(body, maxLines: 12))
                    }
                }
                if (!bodies.isEmpty()) {
                    return LspProbeResult(true, false, command, "LSP probe returned JSON-RPC responses, but initialize did not succeed cleanly.", shortPreview(bodies[0], maxLines: 12))
                }
                return LspProbeResult(true, false, command, "LSP probe produced no parseable JSON-RPC response.", shortPreview(stderr, maxLines: 12))
            } catch (e: Exception) {
                return LspProbeResult(true, false, command, "LSP probe failed.", shortPreview(e.toString(), maxLines: 12))
            }
    }
}
