// AST 编辑与代码分析
// 提供基于 tree-sitter 的 AST 节点匹配、坐标偏移计算、节点替换，
// 以及逐级回退的仓颉源文件分析能力（tree-sitter → cjlint → cjc）。
package cangjiecoder.analysis

import std.collection.*
import std.convert.*
import std.env.*
import std.fs.*
import std.process.*
import cjtreesitter.*

// ── 数据类型 ───────────────────────────────────────────

// AST 节点匹配结果，记录 tree-sitter 输出中解析到的节点类型和起止位置
public struct AstNodeMatch {
    public AstNodeMatch(public let nodeType: String,
                        public let startLine: Int64,
                        public let startColumn: Int64,
                        public let endLine: Int64,
                        public let endColumn: Int64) {}
}

// 分析结果，包含所使用的分析引擎名称、是否成功、摘要和输出预览
public struct AnalysisResult {
    public AnalysisResult(public let engine: String,
                          public let success: Bool,
                          public let summary: String,
                          public let output: String) {}
}

// ── 文本切片 ───────────────────────────────────────────

// 安全的字符串切片，当范围无效时返回空字符串
public func sliceText(text: String, start: Int64, endExclusive: Int64): String {
    if (endExclusive <= start) {
        return ""
    }
    return text[start..endExclusive]
}

// ── tree-sitter 输出解析 ──────────────────────────────

// 从 tree-sitter 输出行中解析一个 [row, column] 坐标对，
// 返回 None 表示该行格式无效（不中断服务，由调用方选择跳过策略）
public func parseNodeCoordinate(line: String, fromIndex: Int64): ?((Int64, Int64), Int64) {
    if (let Some(open) <- line.indexOf("[", fromIndex) &&
        let Some(comma) <- line.indexOf(",", open) &&
        let Some(close) <- line.indexOf("]", comma)) {
        try {
            let row = Int64.parse(sliceText(line, open + 1, comma).trimAscii())
            let column = Int64.parse(sliceText(line, comma + 1, close).trimAscii())
            return ((row, column), close + 1)
        } catch (_: Exception) {
            return None
        }
    }
    return None
}

// 从 tree-sitter parse 输出中提取所有匹配指定节点类型的 AST 节点
public func parseTreeSitterNodeMatches(output: String, nodeType: String): Array<AstNodeMatch> {
    let matches = ArrayList<AstNodeMatch>()
    let pattern = "${nodeType} ["
    for (line in output.lines()) {
        let trimmed = line.trimAscii()
        if (!trimmed.contains(pattern)) {
            continue
        }
        // 使用 if-let 链式解析两组坐标，任一解析失败则跳过该行
        if (let Some(startCoord) <- parseNodeCoordinate(trimmed, 0)) {
            let ((startLine, startColumn), nextIndex) = startCoord
            if (let Some(endCoord) <- parseNodeCoordinate(trimmed, nextIndex)) {
                let ((endLine, endColumn), _) = endCoord
                matches.add(AstNodeMatch(nodeType, startLine, startColumn, endLine, endColumn))
            }
        }
    }
    return matches.toArray()
}

// ── 坐标 → 字节偏移转换 ──────────────────────────────

// 将 0-based 行列坐标转换为字节偏移量，同时兼容 LF 和 CRLF 换行符。
// 当坐标超出文本范围时返回 None 而非抛出异常，避免中断服务。
public func offsetForPoint(text: String, line: Int64, column: Int64): ?Int64 {
    var currentLine: Int64 = 0
    var currentColumn: Int64 = 0
    var offset: Int64 = 0
    let bytes = text.toArray()
    var index: Int64 = 0
    while (index < bytes.size) {
        // 到达目标坐标，直接返回当前偏移
        if (currentLine == line && currentColumn == column) {
            return offset
        }
        let byte = bytes[index]
        // 处理 CRLF 双字节换行
        if (byte == b'\r' && index + 1 < bytes.size && bytes[index + 1] == b'\n') {
            currentLine += 1
            currentColumn = 0
            index += 2
            offset += 2
            continue
        }
        // 处理 LF 单字节换行
        if (byte == b'\n') {
            currentLine += 1
            currentColumn = 0
        } else {
            currentColumn += 1
        }
        index += 1
        offset += 1
    }
    // 检查文件末尾是否恰好是目标坐标
    if (currentLine == line && currentColumn == column) {
        return offset
    }
    return None
}

// ── AST 节点编辑 ─────────────────────────────────────

// 通过内置 tree-sitter FFI 定位指定类型的 AST 节点并替换其内容。
// 使用 queryNodes() 获取节点的字节偏移范围，无需外部 CLI 工具。
// index 用于在多个匹配中选择目标节点（0-based）。
public func editAstNode(repoRoot: String,
                 path: String,
                 nodeType: String,
                 replacement: String,
                 index!: Int64 = 0): String {
    if (let Some(fullPath) <- analysisEnsureWorkspacePath(repoRoot, path)) {
        let source = analysisReadTextFile(fullPath)
        let nodes = queryNodes(source, nodeType)
        if (nodes.isEmpty()) {
            return "No AST node matched type ${nodeType}"
        }
        if (index < 0 || index >= nodes.size) {
            return "AST node index ${index} is out of range; matched ${nodes.size} nodes"
        }

        let target = nodes[index]
        let bytes = source.toArray()
        let startOffset = Int64(target.startByte)
        let endOffset = Int64(target.endByte)

        if (startOffset < 0 || endOffset > bytes.size || startOffset >= endOffset) {
            return "AST node byte offset out of range at ${path}"
        }

        let updatedBytes = ArrayList<Byte>()
        updatedBytes.add(all: bytes[0..startOffset])
        updatedBytes.add(all: replacement.toArray())
        updatedBytes.add(all: bytes[endOffset..bytes.size])
        analysisWriteTextFile(fullPath, String.fromUtf8(updatedBytes.toArray()))
        return "updated AST node ${nodeType} at ${path}:${target.startRow}:${target.startColumn}"
    }
    return "Path does not exist or escapes repository root: ${path}"
}

// 判断 AST 编辑结果是否成功（不包含任何已知错误前缀）
public func astEditSucceeded(message: String): Bool {
    return !message.contains("No AST node matched") &&
        !message.contains("Path does not exist") &&
        !message.contains("escapes repository root") &&
        !message.contains("AST node byte offset out of range") &&
        !message.contains("AST node index")
}

// ── 逐级分析 ─────────────────────────────────────────

// 逐级尝试更丰富的分析器（tree-sitter → cjlint → cjc），
// 按优先级返回首个可用的分析结果，确保在不同工具链环境下均有分析信号。
public func analyzeCangjieFile(repoRoot: String, path: String): AnalysisResult {
    if (let Some(fullPath) <- analysisEnsureWorkspacePath(repoRoot, path)) {
        // 第一级：tree-sitter 解析
        if (let Some(result) <- tryTreeSitterAnalysis(fullPath, repoRoot)) {
            return result
        }

        // 第二级：cjlint 静态检查
        if (let Some(result) <- tryCjlintAnalysis(fullPath, repoRoot)) {
            return result
        }

        // 第三级：cjc 编译检查
        return tryCjcAnalysis(fullPath, repoRoot)
    }
    return AnalysisResult("fallback", false,
        "Path does not exist or escapes repository root: ${path}", "")
}

// 尝试使用 tree-sitter 进行分析，返回 None 表示该引擎不可用需继续尝试下一级
func tryTreeSitterAnalysis(fullPath: String, repoRoot: String): ?AnalysisResult {
    let command = getVariable("TREE_SITTER_CANGJIE") ?? "tree-sitter"
    let (ok, stdout, stderr) = analysisRunCommand(command, ["parse", fullPath], repoRoot)
    if (ok) {
        return AnalysisResult("tree-sitter", true,
            "Tree-sitter parse succeeded",
            analysisShortPreview(stdout, maxLines: 12))
    }
    if (!stderr.trimAscii().isEmpty()) {
        return AnalysisResult("tree-sitter", false,
            "Tree-sitter parse failed. Configure TREE_SITTER_CANGJIE to point to a Cangjie-enabled tree-sitter CLI.",
            analysisShortPreview(stderr, maxLines: 12))
    }
    return None
}

// 尝试使用 cjlint 进行分析，返回 None 表示该引擎不可用需继续尝试下一级
func tryCjlintAnalysis(fullPath: String, repoRoot: String): ?AnalysisResult {
    let command = getVariable("CJLINT_COMMAND") ?? "cjlint"
    let (ok, stdout, stderr) = analysisRunCommand(command, [fullPath], repoRoot)
    if (ok) {
        return AnalysisResult("cjlint", true,
            "cjlint completed",
            analysisShortPreview(stdout, maxLines: 12))
    }
    if (!stdout.trimAscii().isEmpty() || !stderr.trimAscii().isEmpty()) {
        return AnalysisResult("cjlint", false,
            "cjlint reported diagnostics",
            analysisShortPreview("${stdout}\n${stderr}", maxLines: 12))
    }
    return None
}

// 尝试使用 cjc 编译器进行语法检查，作为最终兜底方案
func tryCjcAnalysis(fullPath: String, repoRoot: String): AnalysisResult {
    let command = getVariable("CJC_COMMAND") ?? "cjc"
    let (ok, stdout, stderr) = analysisRunCommand(command, [fullPath], repoRoot)
    if (ok) {
        return AnalysisResult("cjc", true,
            "cjc syntax check succeeded",
            analysisShortPreview(stdout, maxLines: 12))
    }
    return AnalysisResult(
        "fallback", false,
        "No precise analyzer is configured. Install tree-sitter or the Cangjie toolchain and set TREE_SITTER_CANGJIE / CJLINT_COMMAND / CJC_COMMAND.",
        analysisShortPreview("${stdout}\n${stderr}", maxLines: 12)
    )
}

// ── 子包内部工具函数（避免对根包循环依赖） ───────────

// 子包内部的工作区路径安全校验，返回 None 表示路径不存在或逃逸了工作区根目录
func analysisEnsureWorkspacePath(repoRoot: String, path: String): ?String {
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

// 子包内部的文件读取
func analysisReadTextFile(path: String): String {
    return String.fromUtf8(File.readFrom(path))
}

// 子包内部的文件写入
func analysisWriteTextFile(path: String, content: String): Unit {
    File.writeTo(path, content.toArray())
}

// 子包内部的命令执行，返回 (是否成功, 标准输出, 标准错误)
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

// 子包内部的工作区相对路径计算
func analysisWorkspaceRelativePath(repoRoot: String, path: String): String {
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

// 子包内部的文本预览截取（跳过空行，最多保留 maxLines 行）
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
