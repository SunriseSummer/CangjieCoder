// MCP 桥接层：构建 McpWorkspaceOps 并提供 McpRuntime 便捷创建入口
package cangjiecoder

import cangjiecoder.lsp.*
import cangjiecoder.mcp.*

// 构建 McpWorkspaceOps，将根包域函数桥接到 MCP 子包
func buildWorkspaceOps(serviceRoot: String): McpWorkspaceOps {
    let registry = SkillRegistry(serviceRoot)
    return McpWorkspaceOps(
        { repoRoot: String, path: String, oldText: String, newText: String =>
            replaceExactText(repoRoot, path, oldText, newText)
        },
        { repoRoot: String, path: String, limit: Int64 =>
            workspaceListFilesJson(repoRoot, path, limit: limit)
        },
        { repoRoot: String, query: String, path: String, limit: Int64 =>
            workspaceSearchTextJson(repoRoot, query, path, limit: limit)
        },
        { repoRoot: String, path: String, content: String, overwrite: Bool =>
            workspaceCreateFileJson(repoRoot, path, content, overwrite: overwrite)
        },
        { repoRoot: String, command: String, arguments: Array<String>, path: String =>
            workspaceRunCommandJson(repoRoot, command, arguments, path)
        },
        { repoRoot: String, path: String =>
            let result = analyzeCangjieFile(repoRoot, path)
            let data = parseJsonObject(analysisJson(result))
            toolResultJson(result.success, result.summary, data: data)
        },
        { svcRoot: String =>
            exampleProjectsJson(svcRoot)
        },
        { svcRoot: String, workspaceRoot: String, path: String =>
            bootstrapJsonParserProject(svcRoot, workspaceRoot, path)
        },
        { _: String, query: String, limit: Int64 =>
            let matches = registry.search(query, limit: limit)
            let data = parseJsonObject(skillsJson(matches))
            toolResultJson(true, "Skills search completed", data: data)
        },
        { repoRoot: String, path: String, nodeType: String, replacement: String, index: Int64 =>
            let message = editAstNode(repoRoot, path, nodeType, replacement, index: index)
            let ok = astEditSucceeded(message)
            toolMessageJson(ok, if (ok) { "AST node edit completed" } else { "AST node edit failed" }, message)
        },
        { repoRoot: String =>
            lspStatusJson(inspectLspStatus(repoRoot))
        },
        { repoRoot: String =>
            lspProbeJson(probeLspServer(repoRoot))
        },
        { repoRoot: String, path: String =>
            lspQueryJson(queryLspDocumentSymbols(repoRoot, path))
        },
        { repoRoot: String, query: String =>
            lspQueryJson(queryLspWorkspaceSymbols(repoRoot, query))
        },
        { repoRoot: String, path: String, line: Int64, column: Int64 =>
            lspQueryJson(queryLspDefinition(repoRoot, path, line, column))
        },
        { path: String =>
            globalBackupStore.backup(path)
        },
        { =>
            globalBackupStore.hasBackups()
        },
        { =>
            globalBackupStore.rollbackAll()
        }
    )
}

// 创建 MCP 运行时（由 http_server、main、test 使用）
func createMcpRuntime(workspaceRoot: String, serviceRoot!: String = ""): McpRuntime {
    let effectiveServiceRoot = if (serviceRoot.trimAscii().isEmpty()) { workspaceRoot } else { serviceRoot }
    return McpRuntime(workspaceRoot, serviceRoot: effectiveServiceRoot, ops: buildWorkspaceOps(effectiveServiceRoot))
}
