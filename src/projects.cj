package cangjiecoder

import std.env.*
import std.fs.*

struct ExampleProjectSpec {
    public ExampleProjectSpec(let id: String,
                              let name: String,
                              let description: String,
                              let templatePath: String) {}
}

struct LspStatus {
    public LspStatus(let available: Bool,
                     let command: String,
                     let summary: String,
                     let sourceHint: String) {}
}

func listExampleProjects(repoRoot: String): Array<ExampleProjectSpec> {
    return [
        ExampleProjectSpec(
            "json_parser",
            "JsonParser 示例项目",
            "一个可直接构建测试的仓颉 JsonParser 示例工程，演示自主生成/扩展仓颉项目的第一步。",
            "${repoRoot}/examples/json_parser"
        )
    ]
}

func findExampleProject(repoRoot: String, projectId: String): ?ExampleProjectSpec {
    let normalizedId = projectId.toAsciiLower().trimAscii()
    for (project in listExampleProjects(repoRoot)) {
        if (project.id == normalizedId) {
            return project
        }
    }
    return None
}

func ensurePlannedWorkspacePath(repoRoot: String, path: String): String {
    let canonicalRoot = canonicalize(repoRoot).toString()
    let fullPath = resolveRepoPath(repoRoot, path)
    let plannedPath = Path(fullPath)
    let parentPath = plannedPath.parent
    if (parentPath.toString().isEmpty() || !exists(parentPath.toString())) {
        throw IllegalArgumentException("Parent directory does not exist: ${parentPath}")
    }
    let canonicalParent = canonicalize(parentPath).toString()
    if (!canonicalParent.startsWith(canonicalRoot)) {
        throw IllegalArgumentException("Path escapes repository root: ${path}")
    }
    return "${canonicalParent}/${plannedPath.fileName}"
}

func bootstrapJsonParserProject(repoRoot: String, destination: String): String {
    let outputPath = ensurePlannedWorkspacePath(repoRoot, destination)
    if (exists(outputPath)) {
        return "Destination already exists: ${outputPath}"
    }

    match (findExampleProject(repoRoot, "json_parser")) {
        case Some(project) =>
            copy(project.templatePath, to: outputPath)
            removeIfExists("${outputPath}/target", recursive: true)
            removeIfExists("${outputPath}/cjpm.lock")
            return "Bootstrapped JsonParser example at ${outputPath}"
        case None =>
            return "JsonParser example template is missing"
    }
}

func resolveLspCommand(repoRoot: String): ?String {
    let explicitCommand = (getVariable("CANGJIE_LSP_COMMAND") ?? "").trimAscii()
    if (!explicitCommand.isEmpty()) {
        return explicitCommand
    }

    let sdkHome = (getVariable("CANGJIE_SDK_HOME") ?? "").trimAscii()
    if (!sdkHome.isEmpty()) {
        let bundledCommand = "${sdkHome}/tools/bin/LSPServer"
        if (exists(bundledCommand)) {
            return bundledCommand
        }
    }

    let (ok, stdout, _) = runCommandWithCapturedOutput("bash", ["-lc", "command -v LSPServer"], repoRoot)
    if (ok) {
        let resolved = stdout.trimAscii()
        if (!resolved.isEmpty()) {
            return resolved
        }
    }
    return None
}

func inspectLspStatus(repoRoot: String): LspStatus {
    match (resolveLspCommand(repoRoot)) {
        case Some(command) =>
            return LspStatus(
                true,
                command,
                "Detected a Cangjie LSP binary. You can wire it into future symbol/hover/diagnostic sessions via CANGJIE_LSP_COMMAND.",
                "SDK 1.0.5 ships LSPServer under tools/bin, and the tools-source package can be used for deeper protocol integration."
            )
        case None =>
            return LspStatus(
                false,
                "",
                "No Cangjie LSP binary was detected. Configure CANGJIE_LSP_COMMAND or CANGJIE_SDK_HOME to enable stronger analysis hooks.",
                "Use the 1.0.5 SDK release or the tools-source package to provide LSPServer."
            )
    }
}
