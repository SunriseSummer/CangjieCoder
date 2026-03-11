// 工作区文件与命令工具
package cangjiecoder.tools

import std.convert.*
import std.fs.*
import stdx.encoding.json.*
import cangjiecoder.common.*
import cangjiecoder.json.*

const WORKSPACE_COMMAND_OUTPUT_PREVIEW_LINES: Int64 = 20
let allowedWorkspaceCommands: Array<String> = ["cjpm", "cjc", "cjlint", "tree-sitter", "find", "grep"]

// 解析工作区内的子目录路径，空路径回退到工作区根目录。
// 路径无效时安全回退到工作区根目录，避免抛出异常终止服务。
func resolveWorkspaceCommandDirectory(repoRoot: String, path: String): String {
    let normalized = path.trimAscii()
    if (normalized.isEmpty()) {
        return repoRoot
    }
    return ensureWorkspacePath(repoRoot, normalized) ?? repoRoot
}

// 列举工作区文件并返回结构化 JSON
public func workspaceListFilesJson(repoRoot: String, path: String, limit!: Int64 = 200): String {
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
public func workspaceSearchTextJson(repoRoot: String, query: String, path: String, limit!: Int64 = 20): String {
    if (query.trimAscii().isEmpty()) {
        return toolMessageJson(false, "workspace.search_text requires a non-empty query", "query must not be empty")
    }

    let startPath = resolveWorkspaceCommandDirectory(repoRoot, path)
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
public func workspaceCreateFileJson(repoRoot: String,
                             path: String,
                             content: String,
                             overwrite!: Bool = false): String {
    if (let Some(fullPath) <- ensurePlannedWorkspacePath(repoRoot, path)) {
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
    return toolMessageJson(false,
        "Workspace file creation rejected",
        "Invalid path or path escapes workspace: ${path}")
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
public func workspaceRunCommandJson(repoRoot: String,
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

// 精确替换文件中的文本（仅允许唯一匹配）
public func replaceExactText(repoRoot: String, path: String, oldText: String, newText: String): String {
    if (oldText.isEmpty()) {
        return "oldText must not be empty"
    }
    if (let Some(fullPath) <- ensureWorkspacePath(repoRoot, path)) {
        let current = readTextFile(fullPath)
        let matches = current.count(oldText)
        if (matches == 0) {
            return "oldText not found"
        }
        if (matches > 1) {
            return "oldText matched ${matches} locations; refusing ambiguous replacement"
        }
        globalBackupStore.backup(fullPath)
        writeTextFile(fullPath, current.replace(oldText, newText))
        return "updated ${fullPath}"
    }
    return "Path does not exist or escapes repository root: ${path}"
}

// ---- 工作区工具处理函数 ----

public func handleReadFile(ctx: McpToolContext, args: JsonObject): String {
    let path = jsonField(args, "path")
    if (let Some(fullPath) <- ensureWorkspacePath(ctx.workspaceRoot, path)) {
        let content = readTextFile(fullPath)
        let data = JsonObject()
        data.put("path", JsonString(workspaceRelativePath(ctx.workspaceRoot, fullPath)))
        data.put("content", JsonString(content))
        data.put("bytes", JsonInt(content.toArray().size))
        return toolResultJson(true, "Read workspace file", data: data)
    }
    return toolMessageJson(false, "File read failed", "Path does not exist or escapes repository root: ${path}")
}

public func handleListFiles(ctx: McpToolContext, args: JsonObject): String {
    return workspaceListFilesJson(ctx.workspaceRoot,
        jsonField(args, "path"),
        limit: parseJsonIntField(args, "limit", fallback: 200))
}

public func handleSearchText(ctx: McpToolContext, args: JsonObject): String {
    return workspaceSearchTextJson(ctx.workspaceRoot,
        jsonField(args, "query"),
        jsonField(args, "path"),
        limit: parseJsonIntField(args, "limit", fallback: 20))
}

public func handleReplaceText(ctx: McpToolContext, args: JsonObject): String {
    let message = replaceExactText(ctx.workspaceRoot,
        jsonField(args, "path"),
        jsonField(args, "oldText"),
        jsonField(args, "newText"))
    let ok = message.startsWith("updated ")
    return toolMessageJson(ok, if (ok) { "Updated workspace file text" } else { "Workspace text replacement rejected" }, message)
}

public func handleCreateFile(ctx: McpToolContext, args: JsonObject): String {
    return workspaceCreateFileJson(ctx.workspaceRoot,
        jsonField(args, "path"),
        jsonField(args, "content"),
        overwrite: parseJsonBoolField(args, "overwrite", fallback: false))
}

public func handleRunBuild(ctx: McpToolContext, args: JsonObject): String {
    return workspaceRunCommandJson(ctx.workspaceRoot, "cjpm", ["build"], jsonField(args, "path"))
}

public func handleRunTest(ctx: McpToolContext, args: JsonObject): String {
    return workspaceRunCommandJson(ctx.workspaceRoot, "cjpm", ["test"], jsonField(args, "path"))
}

public func handleRunCommand(ctx: McpToolContext, args: JsonObject): String {
    return workspaceRunCommandJson(ctx.workspaceRoot,
        jsonField(args, "command"),
        jsonStringArrayField(args, "args"),
        jsonField(args, "path"))
}

public func handleRollback(ctx: McpToolContext, _: JsonObject): String {
    if (!globalBackupStore.hasBackups()) {
        return toolMessageJson(true, "No file modifications to roll back", "No backups exist")
    }
    let restored = globalBackupStore.rollbackAll()
    let data = JsonObject()
    let restoredArray = JsonArray()
    for (path in restored) {
        restoredArray.add(JsonString(workspaceRelativePath(ctx.workspaceRoot, path)))
    }
    data.put("restoredFiles", restoredArray)
    data.put("count", JsonInt(restored.size))
    return toolResultJson(true, "Rolled back ${restored.size} file(s) to pre-edit state", data: data)
}

// workspace.set_root 和 workspace.get_root 的占位处理函数。
// 实际逻辑在 mcp_handlers.cj 的 handleToolsCall 中直接处理（需访问 McpRuntime）。
public func handleWorkspaceRootPlaceholder(_: McpToolContext, _: JsonObject): String {
    return toolMessageJson(false, "Internal routing error",
        "workspace.set_root and workspace.get_root must be handled by McpRuntime, not the tool registry")
}
