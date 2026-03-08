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
    if (parentPath.toString().isEmpty() || !exists(parentPath.toString())) {
        throw IllegalArgumentException("Parent directory does not exist: ${parentPath}")
    }
    let canonicalParent = canonicalize(parentPath).toString()
    if (!canonicalParent.startsWith(canonicalRoot)) {
        throw IllegalArgumentException("Path escapes repository root: ${path}")
    }
    return "${canonicalParent}/${plannedPath.fileName}"
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
