package cangjiecoder

import std.collection.*
import std.convert.*
import std.fs.*
import std.process.*
import std.env.*

struct AppConfig {
    public AppConfig(let repoRoot: String, let host: String, let port: UInt16) {}
}

struct SkillRecord {
    public SkillRecord(let id: String,
                       let name: String,
                       let description: String,
                       let preview: String,
                       let path: String) {}
}

struct ProviderSpec {
    public ProviderSpec(let name: String,
                        let displayName: String,
                        let baseUrl: String,
                        let apiKeyEnv: String,
                        let defaultModel: String) {}
}

struct AnalysisResult {
    public AnalysisResult(let engine: String,
                          let success: Bool,
                          let summary: String,
                          let output: String) {}
}

func parseConfig(args: Array<String>): AppConfig {
    var repoRoot = getWorkingDirectory().toString()
    var host = "127.0.0.1"
    var port: UInt16 = 8080
    var index = 0
    while (index < args.size) {
        let current = args[index]
        if (current == "--repo") {
            if (index + 1 < args.size) {
                repoRoot = args[index + 1]
                index += 1
            }
        } else if (current == "--host") {
            if (index + 1 < args.size) {
                host = args[index + 1]
                index += 1
            }
        } else if (current == "--port") {
            if (index + 1 < args.size) {
                port = UInt16.parse(args[index + 1])
                index += 1
            }
        }
        index += 1
    }
    return AppConfig(canonicalize(repoRoot).toString(), host, port)
}

func resolveRepoPath(repoRoot: String, path: String): String {
    if (path.startsWith("/")) {
        return path
    }
    return "${repoRoot}/${path}"
}

func ensureWorkspacePath(repoRoot: String, path: String): String {
    let canonicalRoot = canonicalize(repoRoot).toString()
    let fullPath = resolveRepoPath(repoRoot, path)
    if (!exists(fullPath)) {
        throw IllegalArgumentException("Path does not exist: ${path}")
    }
    let canonicalPath = canonicalize(fullPath).toString()
    if (!canonicalPath.startsWith(canonicalRoot)) {
        throw IllegalArgumentException("Path escapes repository root: ${path}")
    }
    return canonicalPath
}

func readTextFile(path: String): String {
    return String.fromUtf8(File.readFrom(path))
}

func writeTextFile(path: String, content: String): Unit {
    File.writeTo(path, content.toArray())
}

func shortPreview(text: String, maxLines!: Int64 = 8): String {
    let lines = ArrayList<String>()
    var count = 0
    for (line in text.lines()) {
        if (line.trimAscii().isEmpty()) {
            continue
        }
        lines.add(line)
        count += 1
        if (count >= maxLines) {
            break
        }
    }
    return String.join(lines.toArray(), delimiter: "\n")
}

func replaceExactText(repoRoot: String, path: String, oldText: String, newText: String): String {
    if (oldText.isEmpty()) {
        return "oldText must not be empty"
    }
    let fullPath = ensureWorkspacePath(repoRoot, path)
    let current = readTextFile(fullPath)
    let matches = current.count(oldText)
    if (matches == 0) {
        return "oldText not found"
    }
    if (matches > 1) {
        return "oldText matched ${matches} locations; refusing ambiguous replacement"
    }
    writeTextFile(fullPath, current.replace(oldText, newText))
    return "updated ${fullPath}"
}

func runCommandWithCapturedOutput(command: String, arguments: Array<String>, workingDirectory: String): (Bool, String, String) {
    try {
        let (status, stdoutBytes, stderrBytes) = executeWithOutput(command,
            arguments,
            workingDirectory: Path(workingDirectory),
            stdOut: Pipe,
            stdErr: Pipe)
        return (status == 0, String.fromUtf8(stdoutBytes), String.fromUtf8(stderrBytes))
    } catch (e: Exception) {
        return (false, "", e.toString())
    }
}
