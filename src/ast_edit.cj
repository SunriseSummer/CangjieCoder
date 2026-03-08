package cangjiecoder

import std.collection.*
import std.convert.*
import std.env.*

struct AstNodeMatch {
    public AstNodeMatch(let nodeType: String,
                        let startLine: Int64,
                        let startColumn: Int64,
                        let endLine: Int64,
                        let endColumn: Int64) {}
}

func sliceText(text: String, start: Int64, endExclusive: Int64): String {
    if (endExclusive <= start) {
        return ""
    }
    return text[start..endExclusive]
}

func parseNodeCoordinate(line: String, fromIndex: Int64): ((Int64, Int64), Int64) {
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

func parseTreeSitterNodeMatches(output: String, nodeType: String): Array<AstNodeMatch> {
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
func offsetForPoint(text: String, line: Int64, column: Int64): Int64 {
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

func editAstNode(repoRoot: String,
                 path: String,
                 nodeType: String,
                 replacement: String,
                 index!: Int64 = 0): String {
    let fullPath = ensureWorkspacePath(repoRoot, path)
    let treeSitterCommand = getVariable("TREE_SITTER_CANGJIE") ?? "tree-sitter"
    let (ok, stdout, stderr) = runCommandWithCapturedOutput(treeSitterCommand, ["parse", fullPath], repoRoot)
    if (!ok) {
        return "tree-sitter unavailable for AST edit: ${shortPreview(stderr, maxLines: 8)}"
    }
    let matches = parseTreeSitterNodeMatches(stdout, nodeType)
    if (matches.isEmpty()) {
        return "No AST node matched type ${nodeType}"
    }
    if (index < 0 || index >= matches.size) {
        return "AST node index ${index} is out of range; matched ${matches.size} nodes"
    }

    let target = matches[index]
    let current = readTextFile(fullPath)
    let startOffset = offsetForPoint(current, target.startLine, target.startColumn)
    let endOffset = offsetForPoint(current, target.endLine, target.endColumn)
    let bytes = current.toArray()
    let updatedBytes = ArrayList<Byte>()
    updatedBytes.add(all: bytes.slice(0, startOffset))
    updatedBytes.add(all: replacement.toArray())
    updatedBytes.add(all: bytes.slice(endOffset, bytes.size - endOffset))
    writeTextFile(fullPath, String.fromUtf8(updatedBytes.toArray()))
    return "updated AST node ${nodeType} at ${path}:${target.startLine}:${target.startColumn}"
}
