package cangjiecoder

import std.fs.*
import std.io.*

struct ExampleProjectSpec {
    public ExampleProjectSpec(let id: String,
                              let name: String,
                              let description: String,
                              let templatePath: String) {}
}

func listExampleProjects(serviceRoot: String): Array<ExampleProjectSpec> {
    let examplesRoot = resolveBundledPath(serviceRoot, "examples")
    return [
        ExampleProjectSpec(
            "json_parser",
            "JsonParser example project",
            "Buildable and testable Cangjie JsonParser example project for the first autonomous project workflow.",
            "${examplesRoot}/json_parser"
        )
    ]
}

func findExampleProject(serviceRoot: String, projectId: String): ?ExampleProjectSpec {
    let normalizedId = projectId.toAsciiLower().trimAscii()
    for (project in listExampleProjects(serviceRoot)) {
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
    if (parentPath.toString().isEmpty()) {
        throw IllegalArgumentException("Parent directory does not exist: ${parentPath}")
    }
    var existingParentPath = parentPath
    var existingParent = existingParentPath.toString()
    while (!existingParent.isEmpty() && !exists(existingParent)) {
        existingParentPath = existingParentPath.parent
        existingParent = existingParentPath.toString()
    }
    if (existingParent.isEmpty()) {
        throw IllegalArgumentException("Parent directory does not exist: ${parentPath}")
    }
    // Validate against the nearest existing ancestor so nested new paths such
    // as target/generated/demo can be created safely without precreating every parent.
    let canonicalParent = canonicalize(existingParent).toString()
    if (!canonicalParent.startsWith(canonicalRoot)) {
        throw IllegalArgumentException("Path escapes repository root: ${path}")
    }
    return fullPath
}

func bootstrapJsonParserProject(serviceRoot: String, workspaceRoot: String, destination: String): String {
    let outputPath = ensurePlannedWorkspacePath(workspaceRoot, destination)
    if (exists(outputPath)) {
        return "Destination already exists: ${outputPath}"
    }

    match (findExampleProject(serviceRoot, "json_parser")) {
        case Some(project) =>
            if (!exists(project.templatePath)) {
                return "JsonParser example template is missing: ${project.templatePath}"
            }
            let outputParent = Path(outputPath).parent.toString()
            if (!outputParent.isEmpty() && !exists(outputParent)) {
                Directory.create(ensurePlannedWorkspacePath(workspaceRoot, outputParent), recursive: true)
            }
            copy(project.templatePath, to: outputPath)
            removeIfExists("${outputPath}/target", recursive: true)
            removeIfExists("${outputPath}/cjpm.lock")
            return "Bootstrapped JsonParser example at ${outputPath}"
        case None =>
            return "JsonParser example template is missing"
    }
}
