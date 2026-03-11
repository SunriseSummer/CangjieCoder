// 工作区文件操作工具：读取、列举、搜索、替换、创建、回滚
package cangjiecoder.workspace

import std.convert.*
import std.fs.*
import stdx.encoding.json.*
import cangjiecoder.common.*
import cangjiecoder.json.*

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

// ---- 工作区文件工具处理函数 ----

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
