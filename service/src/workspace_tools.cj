package cangjiecoder

import std.convert.*
import std.env.*
import std.fs.*
import stdx.encoding.json.*

const WORKSPACE_COMMAND_OUTPUT_PREVIEW_LINES: Int64 = 20
let allowedWorkspaceCommands: Array<String> = ["cjpm", "cjc", "cjlint", "tree-sitter", "find", "grep"]

// 判断 AST 编辑结果是否成功（无错误前缀）
func astEditSucceeded(message: String): Bool {
    return !message.startsWith("tree-sitter unavailable") &&
        !message.contains("No AST node matched") &&
        !message.contains("Path does not exist") &&
        !message.contains("escapes repository root")
}

// 逐级尝试更丰富的分析器（tree-sitter → cjlint → cjc），返回最佳可用信号
func analyzeCangjieFile(repoRoot: String, path: String): AnalysisResult {
    let fullPath = ensureWorkspacePath(repoRoot, path)
    let treeSitterCommand = getVariable("TREE_SITTER_CANGJIE") ?? "tree-sitter"
    let (treeOk, treeStdout, treeStderr) = runCommandWithCapturedOutput(treeSitterCommand,
        ["parse", fullPath],
        repoRoot)
    if (treeOk) {
        return AnalysisResult("tree-sitter", true, "Tree-sitter parse succeeded", shortPreview(treeStdout, maxLines: 12))
    }
    if (!treeStderr.trimAscii().isEmpty()) {
        return AnalysisResult("tree-sitter", false,
            "Tree-sitter parse failed. Configure TREE_SITTER_CANGJIE to point to a Cangjie-enabled tree-sitter CLI.",
            shortPreview(treeStderr, maxLines: 12))
    }

    let lintCommand = getVariable("CJLINT_COMMAND") ?? "cjlint"
    let (lintOk, lintStdout, lintStderr) = runCommandWithCapturedOutput(lintCommand, [fullPath], repoRoot)
    if (lintOk) {
        return AnalysisResult("cjlint", true, "cjlint completed", shortPreview(lintStdout, maxLines: 12))
    }
    if (!lintStdout.trimAscii().isEmpty() || !lintStderr.trimAscii().isEmpty()) {
        return AnalysisResult("cjlint", false, "cjlint reported diagnostics", shortPreview("${lintStdout}\n${lintStderr}", maxLines: 12))
    }

    let compileCommand = getVariable("CJC_COMMAND") ?? "cjc"
    let (compileOk, compileStdout, compileStderr) = runCommandWithCapturedOutput(compileCommand, [fullPath], repoRoot)
    if (compileOk) {
        return AnalysisResult("cjc", true, "cjc syntax check succeeded", shortPreview(compileStdout, maxLines: 12))
    }

    return AnalysisResult(
        "fallback",
        false,
        "No precise analyzer is configured. Install tree-sitter or the Cangjie toolchain and set TREE_SITTER_CANGJIE / CJLINT_COMMAND / CJC_COMMAND.",
        shortPreview("${compileStdout}\n${compileStderr}", maxLines: 12)
    )
}

// 解析工作区内的子目录路径，空路径回退到工作区根目录
func resolveWorkspaceCommandDirectory(repoRoot: String, path: String): String {
    let normalized = path.trimAscii()
    if (normalized.isEmpty()) {
        return repoRoot
    }
    return ensureWorkspacePath(repoRoot, normalized)
}

// 列举工作区文件并返回结构化 JSON
func workspaceListFilesJson(repoRoot: String, path: String, limit!: Int64 = 200): String {
    let startPath = resolveWorkspaceCommandDirectory(repoRoot, path)
    let (status, stdout, stderr) = runCommandDetailedOutput("find", [startPath, "-type", "f"], repoRoot)
    if (status != 0) {
        return toolCommandResultJson("find", [startPath, "-type", "f"], repoRoot, status, stdout, stderr)
    }

    let files = JsonArray()
    var count: Int64 = 0
    for (line in stdout.lines()) {
        let trimmed = line.trimAscii()
        if (trimmed.isEmpty()) {
            continue
        }
        if (count >= limit) {
            break
        }
        files.add(JsonString(workspaceRelativePath(repoRoot, trimmed)))
        count += 1
    }

    let data = JsonObject()
    data.put("path", JsonString(workspaceRelativePath(repoRoot, startPath)))
    data.put("count", JsonInt(count))
    data.put("files", files)
    return toolResultJson(true, "Listed workspace files", data: data)
}

// 在工作区中搜索文本并返回匹配结果
func workspaceSearchTextJson(repoRoot: String, query: String, path: String, limit!: Int64 = 20): String {
    if (query.trimAscii().isEmpty()) {
        return toolMessageJson(false, "workspace.search_text requires a non-empty query", "query must not be empty")
    }

    let startPath = resolveWorkspaceCommandDirectory(repoRoot, path)
    // -R: 递归搜索; -n: 显示行号; -I: 跳过二进制文件; -F: 固定字符串匹配
    let arguments = ["-R", "-n", "-I", "-F", query, startPath]
    let (status, stdout, stderr) = runCommandDetailedOutput("grep", arguments, repoRoot)
    if (status != 0 && status != 1) {
        return toolCommandResultJson("grep", arguments, repoRoot, status, stdout, stderr)
    }

    let matches = JsonArray()
    var count: Int64 = 0
    for (line in stdout.lines()) {
        let firstColon = match (line.indexOf(":")) {
            case Some(value) => value
            case None => continue
        }
        let secondColon = match (line.indexOf(":", firstColon + 1)) {
            case Some(value) => value
            case None => continue
        }
        let filePath = line[0..firstColon]
        let lineNumber = line[firstColon + 1..secondColon]
        let preview = line[secondColon + 1..line.size]
        var parsedLine: Int64 = 0
        try {
            parsedLine = Int64.parse(lineNumber)
        } catch (e: Exception) {
            parsedLine = 0
        }
        let item = JsonObject()
        item.put("path", JsonString(workspaceRelativePath(repoRoot, filePath)))
        item.put("line", JsonInt(parsedLine))
        item.put("preview", JsonString(preview))
        matches.add(item)
        count += 1
        if (count >= limit) {
            break
        }
    }

    let data = JsonObject()
    data.put("query", JsonString(query))
    data.put("path", JsonString(workspaceRelativePath(repoRoot, startPath)))
    data.put("count", JsonInt(count))
    data.put("matches", matches)
    return toolResultJson(true, if (count == 0) { "No workspace matches found" } else { "Found workspace text matches" }, data: data)
}

// 在工作区中创建文件，默认禁止覆盖已有文件
func workspaceCreateFileJson(repoRoot: String,
                             path: String,
                             content: String,
                             overwrite!: Bool = false): String {
    let fullPath = ensurePlannedWorkspacePath(repoRoot, path)
    let existedBefore = exists(fullPath)
    let parentPath = Path(fullPath).parent.toString()
    if (!parentPath.isEmpty() && !exists(parentPath)) {
        Directory.create(parentPath, recursive: true)
    }
    if (existedBefore && !overwrite) {
        return toolMessageJson(false,
            "Workspace file creation rejected",
            "Path already exists: ${workspaceRelativePath(repoRoot, fullPath)}")
    }
    // 覆盖前自动备份原始内容，支持事务回滚
    if (existedBefore && overwrite) {
        globalBackupStore.backup(fullPath)
    }
    writeTextFile(fullPath, content)
    let data = JsonObject()
    data.put("path", JsonString(workspaceRelativePath(repoRoot, fullPath)))
    data.put("bytes", JsonInt(content.toArray().size))
    data.put("overwritten", JsonBool(existedBefore && overwrite))
    return toolResultJson(true, "Created workspace file", data: data)
}

// 检查命令是否在工作区安全白名单中
func isAllowedWorkspaceCommand(command: String): Bool {
    let normalized = command.trimAscii().toAsciiLower()
    for (allowed in allowedWorkspaceCommands) {
        if (normalized == allowed) {
            return true
        }
    }
    return false
}

// 在工作区内执行白名单命令并返回结构化结果
func workspaceRunCommandJson(repoRoot: String,
                             command: String,
                             arguments: Array<String>,
                             path: String): String {
    let normalizedCommand = command.trimAscii()
    if (!isAllowedWorkspaceCommand(normalizedCommand)) {
        return toolMessageJson(false,
            "Command is not allowed for workspace.run_command",
            "Allowed commands: cjpm, cjc, cjlint, tree-sitter, find, grep")
    }

    let workingDirectory = resolveWorkspaceCommandDirectory(repoRoot, path)
    let (status, stdout, stderr) = runCommandDetailedOutput(normalizedCommand, arguments, workingDirectory)
    return toolCommandResultJson(normalizedCommand, arguments, workingDirectory, status, stdout, stderr)
}
