// MCP 工具注册表：将工具名映射到处理函数
package cangjiecoder.tools

import std.collection.*

public func buildMcpToolRegistry(): HashMap<String, McpToolHandler> {
    let registry = HashMap<String, McpToolHandler>()
    registry["skills.search"] = handleSkillsSearch
    registry["skills.batch_search"] = handleSkillsBatchSearch
    registry["skills.prompt_context"] = handleSkillsPromptContext
    registry["workspace.read_file"] = handleReadFile
    registry["workspace.list_files"] = handleListFiles
    registry["workspace.search_text"] = handleSearchText
    registry["workspace.replace_text"] = handleReplaceText
    registry["workspace.create_file"] = handleCreateFile
    registry["workspace.run_build"] = handleRunBuild
    registry["workspace.run_test"] = handleRunTest
    registry["workspace.run_command"] = handleRunCommand
    registry["cangjie.analyze_file"] = handleAnalyzeFile
    registry["cangjie.lsp_status"] = handleLspStatus
    registry["cangjie.lsp_probe"] = handleLspProbe
    registry["cangjie.lsp_document_symbols"] = handleLspDocumentSymbols
    registry["cangjie.lsp_workspace_symbols"] = handleLspWorkspaceSymbols
    registry["cangjie.lsp_definition"] = handleLspDefinition
    registry["cangjie.edit_ast_node"] = handleEditAstNode
    registry["workspace.rollback"] = handleRollback
    // workspace.set_root 和 workspace.get_root 在 handleToolsCall 中直接处理（需访问 McpRuntime），
    // 此处注册占位处理函数以保持工具定义与注册表一致。
    registry["workspace.set_root"] = handleWorkspaceRootPlaceholder
    registry["workspace.get_root"] = handleWorkspaceRootPlaceholder
    registry["cangjie.ast_parse"] = handleAstParse
    registry["cangjie.ast_query_nodes"] = handleAstQueryNodes
    registry["cangjie.ast_list_nodes"] = handleAstListNodes
    registry["cangjie.ast_summary"] = handleAstSummary
    registry["cangjie.ast_query_nodes_with_text"] = handleAstQueryNodesWithText
    return registry
}
