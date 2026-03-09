package cangjiecoder

import std.collection.*
import std.fs.*
import std.process.*

const APP_VERSION: String = "0.3.0"

struct AppConfig {
    public AppConfig(let workspaceRoot: String,
                     let serviceRoot: String,
                     let host: String,
                     let port: UInt16) {}
}

struct SkillRecord {
    public SkillRecord(let id: String,
                       let name: String,
                       let description: String,
                       let preview: String,
                       let path: String) {}
}

struct AnalysisResult {
    public AnalysisResult(let engine: String,
                          let success: Bool,
                          let summary: String,
                          let output: String) {}
}

func resolveBundledPath(serviceRoot: String, relativePath: String): String {
    let bundledPath = "${serviceRoot}/${relativePath}"
    if (exists(bundledPath)) {
        return canonicalize(bundledPath).toString()
    }

    let parentBundledPath = "${serviceRoot}/../${relativePath}"
    if (exists(parentBundledPath)) {
        return canonicalize(parentBundledPath).toString()
    }
    return bundledPath
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

// Convert an absolute or in-repo path into a workspace-relative path.
// Returns "." when the path is the workspace root, and intentionally returns the original input unchanged for non-existent paths.
func workspaceRelativePath(repoRoot: String, path: String): String {
    let canonicalRoot = canonicalize(repoRoot).toString()
    let canonicalPath = if (exists(path)) {
        canonicalize(path).toString()
    } else {
        path
    }
    if (canonicalPath == canonicalRoot) {
        return "."
    }
    let prefix = "${canonicalRoot}/"
    if (canonicalPath.startsWith(prefix)) {
        return canonicalPath[prefix.size..canonicalPath.size]
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

// FileBackupStore 在修改文件前保存原始内容，支持事务回滚。
// 当 build/test 验证失败时，可以将被破坏的文件恢复到修改前的状态。
class FileBackupStore {
    let backups = HashMap<String, String>()

    // 在修改文件前备份其当前内容。同一个文件只保存首次备份，
    // 确保回滚时恢复到事务开始前的初始状态。
    public func backup(path: String): Unit {
        if (backups.contains(path)) {
            return
        }
        if (exists(path)) {
            backups[path] = readTextFile(path)
        }
    }

    // 将所有已备份文件恢复到修改前的状态
    public func rollbackAll(): Array<String> {
        let restored = ArrayList<String>()
        for ((path, content) in backups) {
            try {
                writeTextFile(path, content)
                restored.add(path)
            } catch (e: Exception) {
                // 恢复失败时静默跳过，避免级联失败
            }
        }
        backups.clear()
        return restored.toArray()
    }

    // 清除所有备份（事务提交成功后调用）
    public func clear(): Unit {
        backups.clear()
    }

    public prop fileCount: Int64 {
        get() {
            return backups.size
        }
    }

    public func hasBackups(): Bool {
        return !backups.isEmpty()
    }

    public func backedUpPaths(): Array<String> {
        let paths = ArrayList<String>()
        for ((path, _) in backups) {
            paths.add(path)
        }
        return paths.toArray()
    }
}

// 全局备份存储实例，被 MCP 工具处理函数共享
var globalBackupStore = FileBackupStore()

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
    // 修改前自动备份，支持事务回滚
    globalBackupStore.backup(fullPath)
    writeTextFile(fullPath, current.replace(oldText, newText))
    return "updated ${fullPath}"
}

func runCommandDetailedOutput(command: String, arguments: Array<String>, workingDirectory: String): (Int64, String, String) {
    try {
        let (status, stdoutBytes, stderrBytes) = executeWithOutput(command,
            arguments,
            workingDirectory: Path(workingDirectory),
            stdOut: Pipe,
            stdErr: Pipe)
        return (status, String.fromUtf8(stdoutBytes), String.fromUtf8(stderrBytes))
    } catch (e: Exception) {
        return (-1, "", e.toString())
    }
}

func runCommandWithCapturedOutput(command: String, arguments: Array<String>, workingDirectory: String): (Bool, String, String) {
    let (status, stdout, stderr) = runCommandDetailedOutput(command, arguments, workingDirectory)
    return (status == 0, stdout, stderr)
}
