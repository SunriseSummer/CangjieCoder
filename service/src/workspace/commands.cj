// 工作区命令执行工具：构建、测试、受限命令
package cangjiecoder.workspace

import stdx.encoding.json.*
import cangjiecoder.common.*
import cangjiecoder.json.*

const WORKSPACE_COMMAND_OUTPUT_PREVIEW_LINES: Int64 = 20
let allowedWorkspaceCommands: Array<String> = ["cjpm", "cjc", "cjlint", "tree-sitter", "find", "grep"]

// 解析工作区内的子目录路径，空路径回退到工作区根目录。
// 路径无效时安全回退到工作区根目录，避免抛出异常终止服务。
public func resolveWorkspaceCommandDirectory(repoRoot: String, path: String): String {
    let normalized = path.trimAscii()
    if (normalized.isEmpty()) {
        return repoRoot
    }
    return ensureWorkspacePath(repoRoot, normalized) ?? repoRoot
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

// ---- 工作区命令工具处理函数 ----

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
