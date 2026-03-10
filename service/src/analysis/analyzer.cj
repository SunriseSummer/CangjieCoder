// AST 编辑与代码分析
package cangjiecoder.analysis

import std.collection.*
import std.convert.*
import std.env.*
import std.fs.*
import std.process.*

public struct AstNodeMatch {
    public AstNodeMatch(public let nodeType: String,
                        public let startLine: Int64,
                        public let startColumn: Int64,
                        public let endLine: Int64,
                        public let endColumn: Int64) {}
}

public struct AnalysisResult {
    public AnalysisResult(public let engine: String,
                          public let success: Bool,
                          public let summary: String,
                          public let output: String) {}
}

public func sliceText(text: String, start: Int64, endExclusive: Int64): String {
    if (endExclusive <= start) {
        return ""
    }
    return text[start..endExclusive]
}

public func parseNodeCoordinate(line: String, fromIndex: Int64): ((Int64, Int64), Int64) {
    try {
        let open = line.indexOf("[", fromIndex).getOrThrow()
        let comma = line.indexOf(",", open).getOrThrow()
        let close = line.indexOf("]", comma).getOrThrow()
        let row = Int64.parse(sliceText(line, open + 1, comma).trimAscii())
        let column = Int64.parse(sliceText(line, comma + 1, close).trimAscii())
        return ((row, column), close + 1)
    } catch (e: Exception) {
        throw IllegalArgumentException("Failed to parse node coordinate from tree-sitter output: ${line}")
    }
}

public func parseTreeSitterNodeMatches(output: String, nodeType: String): Array<AstNodeMatch> {
    let matches = ArrayList<AstNodeMatch>()
    for (line in output.lines()) {
        let trimmed = line.trimAscii()
        if (!trimmed.contains("${nodeType} [")) {
            continue
        }
        try {
            let ((startLine, startColumn), nextIndex) = parseNodeCoordinate(trimmed, 0)
            let ((endLine, endColumn), _) = parseNodeCoordinate(trimmed, nextIndex)
            matches.add(AstNodeMatch(nodeType, startLine, startColumn, endLine, endColumn))
        } catch (e: Exception) {
            continue
        }
    }
    return matches.toArray()
}

// Convert 0-based line:column coordinates into byte offsets and treat both LF and CRLF as line breaks.
public func offsetForPoint(text: String, line: Int64, column: Int64): Int64 {
    var currentLine: Int64 = 0
    var currentColumn: Int64 = 0
    var offset: Int64 = 0
    let bytes = text.toArray()
    var index: Int64 = 0
    while (index < bytes.size) {
        if (currentLine == line && currentColumn == column) {
            return offset
        }
        let byte = bytes[index]
        if (byte == b'\r' && index + 1 < bytes.size && bytes[index + 1] == b'\n') {
            currentLine += 1
            currentColumn = 0
            index += 2
            offset += 2
            continue
        }
        if (byte == b'\n') {
            currentLine += 1
            currentColumn = 0
        } else {
            currentColumn += 1
        }
        index += 1
        offset += 1
    }
    if (currentLine == line && currentColumn == column) {
        return offset
    }
    throw IllegalArgumentException("Line:column coordinate ${line}:${column} exceeds file bounds (max reachable point: ${currentLine}:${currentColumn})")
}

public func editAstNode(repoRoot: String,
                 path: String,
                 nodeType: String,
                 replacement: String,
                 index!: Int64 = 0): String {
    let fullPath = analysisEnsureWorkspacePath(repoRoot, path)
    let treeSitterCommand = getVariable("TREE_SITTER_CANGJIE") ?? "tree-sitter"
    let (ok, stdout, stderr) = analysisRunCommand(treeSitterCommand, ["parse", fullPath], repoRoot)
    if (!ok) {
        return "tree-sitter unavailable for AST edit: ${analysisShortPreview(stderr, maxLines: 8)}"
    }
    let matches = parseTreeSitterNodeMatches(stdout, nodeType)
    if (matches.isEmpty()) {
        return "No AST node matched type ${nodeType}"
    }
    if (index < 0 || index >= matches.size) {
        return "AST node index ${index} is out of range; matched ${matches.size} nodes"
    }

    let target = matches[index]
    let current = analysisReadTextFile(fullPath)
    let startOffset = offsetForPoint(current, target.startLine, target.startColumn)
    let endOffset = offsetForPoint(current, target.endLine, target.endColumn)
    let bytes = current.toArray()
    let updatedBytes = ArrayList<Byte>()
    updatedBytes.add(all: bytes.slice(0, startOffset))
    updatedBytes.add(all: replacement.toArray())
    updatedBytes.add(all: bytes.slice(endOffset, bytes.size - endOffset))
    analysisWriteTextFile(fullPath, String.fromUtf8(updatedBytes.toArray()))
    return "updated AST node ${nodeType} at ${path}:${target.startLine}:${target.startColumn}"
}

// 判断 AST 编辑结果是否成功（无错误前缀）
public func astEditSucceeded(message: String): Bool {
    return !message.startsWith("tree-sitter unavailable") &&
        !message.contains("No AST node matched") &&
        !message.contains("Path does not exist") &&
        !message.contains("escapes repository root")
}

// 逐级尝试更丰富的分析器（tree-sitter → cjlint → cjc），返回最佳可用信号
public func analyzeCangjieFile(repoRoot: String, path: String): AnalysisResult {
    let fullPath = analysisEnsureWorkspacePath(repoRoot, path)
    let treeSitterCommand = getVariable("TREE_SITTER_CANGJIE") ?? "tree-sitter"
    let (treeOk, treeStdout, treeStderr) = analysisRunCommand(treeSitterCommand,
        ["parse", fullPath],
        repoRoot)
    if (treeOk) {
        return AnalysisResult("tree-sitter", true, "Tree-sitter parse succeeded", analysisShortPreview(treeStdout, maxLines: 12))
    }
    if (!treeStderr.trimAscii().isEmpty()) {
        return AnalysisResult("tree-sitter", false,
            "Tree-sitter parse failed. Configure TREE_SITTER_CANGJIE to point to a Cangjie-enabled tree-sitter CLI.",
            analysisShortPreview(treeStderr, maxLines: 12))
    }

    let lintCommand = getVariable("CJLINT_COMMAND") ?? "cjlint"
    let (lintOk, lintStdout, lintStderr) = analysisRunCommand(lintCommand, [fullPath], repoRoot)
    if (lintOk) {
        return AnalysisResult("cjlint", true, "cjlint completed", analysisShortPreview(lintStdout, maxLines: 12))
    }
    if (!lintStdout.trimAscii().isEmpty() || !lintStderr.trimAscii().isEmpty()) {
        return AnalysisResult("cjlint", false, "cjlint reported diagnostics", analysisShortPreview("${lintStdout}\n${lintStderr}", maxLines: 12))
    }

    let compileCommand = getVariable("CJC_COMMAND") ?? "cjc"
    let (compileOk, compileStdout, compileStderr) = analysisRunCommand(compileCommand, [fullPath], repoRoot)
    if (compileOk) {
        return AnalysisResult("cjc", true, "cjc syntax check succeeded", analysisShortPreview(compileStdout, maxLines: 12))
    }

    return AnalysisResult(
        "fallback",
        false,
        "No precise analyzer is configured. Install tree-sitter or the Cangjie toolchain and set TREE_SITTER_CANGJIE / CJLINT_COMMAND / CJC_COMMAND.",
        analysisShortPreview("${compileStdout}\n${compileStderr}", maxLines: 12)
    )
}

// 子包内部工具函数副本（避免对根包循环依赖）
func analysisEnsureWorkspacePath(repoRoot: String, path: String): String {
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

func analysisReadTextFile(path: String): String {
    return String.fromUtf8(File.readFrom(path))
}

func analysisWriteTextFile(path: String, content: String): Unit {
    File.writeTo(path, content.toArray())
}

func analysisRunCommand(command: String, arguments: Array<String>, workingDirectory: String): (Bool, String, String) {
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

func analysisShortPreview(text: String, maxLines!: Int64 = 8): String {
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
