// 项目模板管理：示例项目列举与引导
package cangjiecoder.projects

import std.fs.*
import std.io.*

public struct ExampleProjectSpec {
    public ExampleProjectSpec(public let id: String,
                              public let name: String,
                              public let description: String,
                              public let templatePath: String) {}
}

public func listExampleProjects(serviceRoot: String): Array<ExampleProjectSpec> {
    let examplesRoot = projectsResolveBundledPath(serviceRoot, "tests")
    return [
        ExampleProjectSpec(
            "json_parser",
            "JsonParser example project",
            "Full recursive-descent JSON parser demonstrating enum, class, ArrayList, pattern matching, string processing, and exception handling.",
            "${examplesRoot}/json_parser"
        ),
        ExampleProjectSpec(
            "todo_list",
            "TodoList CLI application",
            "Todo list manager demonstrating struct, enum, ArrayList, pattern matching, filtering, sorting, and formatted output.",
            "${examplesRoot}/todo_list"
        ),
        ExampleProjectSpec(
            "calculator",
            "Expression calculator",
            "Arithmetic expression calculator demonstrating recursive enum AST, recursive-descent parsing, operator precedence, and expression evaluation.",
            "${examplesRoot}/calculator"
        )
    ]
}

public func findExampleProject(serviceRoot: String, projectId: String): ?ExampleProjectSpec {
    let normalizedId = projectId.toAsciiLower().trimAscii()
    for (project in listExampleProjects(serviceRoot)) {
        if (project.id == normalizedId) {
            return project
        }
    }
    return None
}

// 校验计划创建的路径是否在工作区内，返回 None 表示父目录不存在或路径逃逸了工作区
public func ensurePlannedWorkspacePath(repoRoot: String, path: String): ?String {
    let canonicalRoot = canonicalize(repoRoot).toString()
    let fullPath = projectsResolveRepoPath(repoRoot, path)
    let plannedPath = Path(fullPath)
    let parentPath = plannedPath.parent
    if (parentPath.toString().isEmpty()) {
        return None
    }
    var existingParentPath = parentPath
    var existingParent = existingParentPath.toString()
    while (!existingParent.isEmpty() && !exists(existingParent)) {
        existingParentPath = existingParentPath.parent
        existingParent = existingParentPath.toString()
    }
    if (existingParent.isEmpty()) {
        return None
    }
    // Validate against the nearest existing ancestor so nested new paths such
    // as target/generated/demo can be created safely without precreating every parent.
    let canonicalParent = canonicalize(existingParent).toString()
    if (!canonicalParent.startsWith(canonicalRoot)) {
        return None
    }
    return fullPath
}

public func bootstrapJsonParserProject(serviceRoot: String, workspaceRoot: String, destination: String): String {
    return bootstrapExampleProject(serviceRoot, workspaceRoot, "json_parser", destination)
}

// 通用示例项目引导：按 projectId 查找模板并复制到目标目录
public func bootstrapExampleProject(serviceRoot: String, workspaceRoot: String, projectId: String, destination: String): String {
    if (let Some(outputPath) <- ensurePlannedWorkspacePath(workspaceRoot, destination)) {
        if (exists(outputPath)) {
            return "Destination already exists: ${outputPath}"
        }

        if (let Some(project) <- findExampleProject(serviceRoot, projectId)) {
            if (!exists(project.templatePath)) {
                return "${project.name} template is missing: ${project.templatePath}"
            }
            let outputParent = Path(outputPath).parent.toString()
            if (!outputParent.isEmpty() && !exists(outputParent)) {
                if (let Some(parentPath) <- ensurePlannedWorkspacePath(workspaceRoot, outputParent)) {
                    Directory.create(parentPath, recursive: true)
                } else {
                    return "Invalid parent path: ${outputParent}"
                }
            }
            copy(project.templatePath, to: outputPath)
            removeIfExists("${outputPath}/target", recursive: true)
            removeIfExists("${outputPath}/cjpm.lock")
            return "Bootstrapped ${project.name} at ${outputPath}"
        }
        return "Example project '${projectId}' not found"
    }
    return "Invalid destination path: ${destination}"
}

// 子包内部工具函数副本（避免对根包循环依赖）
func projectsResolveBundledPath(serviceRoot: String, relativePath: String): String {
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

func projectsResolveRepoPath(repoRoot: String, path: String): String {
    if (path.startsWith("/")) {
        return path
    }
    return "${repoRoot}/${path}"
}
