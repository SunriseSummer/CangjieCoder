// 共享工具函数：路径处理、文件读写、命令执行、文本处理
package cangjiecoder.common

import std.collection.*
import std.fs.*
import std.process.*

public func resolveBundledPath(serviceRoot: String, relativePath: String): String {
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

public func resolveRepoPath(repoRoot: String, path: String): String {
    if (path.startsWith("/")) {
        return path
    }
    return "${repoRoot}/${path}"
}

public func ensureWorkspacePath(repoRoot: String, path: String): String {
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
public func workspaceRelativePath(repoRoot: String, path: String): String {
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

public func readTextFile(path: String): String {
    return String.fromUtf8(File.readFrom(path))
}

public func writeTextFile(path: String, content: String): Unit {
    File.writeTo(path, content.toArray())
}

public func shortPreview(text: String, maxLines!: Int64 = 8): String {
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

public func runCommandDetailedOutput(command: String, arguments: Array<String>, workingDirectory: String): (Int64, String, String) {
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

public func runCommandWithCapturedOutput(command: String, arguments: Array<String>, workingDirectory: String): (Bool, String, String) {
    let (status, stdout, stderr) = runCommandDetailedOutput(command, arguments, workingDirectory)
    return (status == 0, stdout, stderr)
}
