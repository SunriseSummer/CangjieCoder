package cangjiecoder

import std.argopt.*
import std.collection.*
import std.convert.*
import std.env.*
import std.fs.*
import cangjiecoder.common.*
import cangjiecoder.lsp.*
import cangjiecoder.skills.*
import cangjiecoder.projects.*
import cangjiecoder.analysis.*
import cangjiecoder.tools.*

// 打印 CLI 用法，列出所有子命令及全局选项
func printUsage(): Unit {
    println("CangjieCoder ${APP_VERSION} - lightweight AI coding tool for Cangjie projects")
    println("")
    println("Usage:")
    println("  cangjiecoder [OPTIONS] <subcommand> [ARGS...]")
    println("")
    println("Subcommands:")
    println("  mcp-stdio                     Start MCP stdio server")
    println("  skills                        List all registered skills")
    println("  skills-search <query>         Search skills by keyword")
    println("  examples                      List example projects")
    println("  bootstrap-json-parser <path>  Generate a JSON parser project at <path>")
    println("  bootstrap <id> <path>         Generate an example project by id at <path>")
    println("  analyze <path>                Analyze a Cangjie source file")
    println("  create-file <path> [content]  Create a new workspace file")
    println("  lsp-status                    Check LSP availability")
    println("  lsp-probe                     Probe the LSP binary")
    println("  lsp-document-symbols <path>   Query document symbols via LSP")
    println("  lsp-workspace-symbols [query] Query workspace symbols via LSP")
    println("  lsp-definition <p> <l> <c>    Query definition via LSP")
    println("  help                          Show this help message")
    println("")
    println("Global Options:")
    println("  -h, --help       Show help message")
    println("  -V, --version    Show version")
    println("  -r, --repo PATH  Target workspace root (default: service directory)")
    println("")
    println("Environment:")
    println("  STDX_PATH            stdx binary dependency directory")
    println("  TREE_SITTER_CANGJIE  tree-sitter command with Cangjie grammar support")
    println("  CJLINT_COMMAND       override cjlint command")
    println("  CJC_COMMAND          override cjc command")
    println("  CANGJIE_LSP_COMMAND  explicit path/command for the Cangjie LSP binary")
    println("  CANGJIE_SDK_HOME     SDK home used to auto-discover tools/bin/LSPServer")
}

// 基于 std.argopt 解析结果构造 AppConfig
func buildAppConfig(options: HashMap<String, String>): AppConfig {
    let serviceRoot = canonicalize(getWorkingDirectory().toString()).toString()
    let workspaceRoot = canonicalize(optionValue(options, "repo", "r", fallback: serviceRoot)).toString()
    return AppConfig(workspaceRoot, serviceRoot)
}

// 获取第 n 个非选项参数，越界时返回空串
func nonOptionAt(nonOptions: Array<String>, index: Int64): String {
    if (index < nonOptions.size) {
        return nonOptions[index]
    }
    return ""
}

// Full 选项使用 --long 或 -s 形式时 key 不同，统一查找
func optionValue(options: HashMap<String, String>, longKey: String, shortKey: String, fallback!: String = ""): String {
    return options.get(longKey) ?? options.get(shortKey) ?? fallback
}

// CLI 子命令处理函数类型：接收配置和非选项参数，返回退出码
type CliSubcommandHandler = (AppConfig, Array<String>) -> Int64

// 打印 LSP 查询结果的通用格式
func printLspQueryResult(result: LspQueryResult): Int64 {
    println(result.summary)
    if (!result.command.isEmpty()) {
        println("command: ${result.command}")
    }
    if (!result.responsePreview.trimAscii().isEmpty()) {
        println(result.responsePreview)
    }
    return if (result.success) { 0 } else { 1 }
}

// 各 CLI 子命令的独立处理函数

func cmdMcpStdio(config: AppConfig, _: Array<String>): Int64 {
    let runtime = createMcpRuntime(config.workspaceRoot, serviceRoot: config.serviceRoot)
    startMcpStdioServer(runtime)
    return 0
}

func cmdSkills(config: AppConfig, _: Array<String>): Int64 {
    let registry = SkillRegistry(config.serviceRoot)
    for (skill in registry.list(limit: 200)) {
        println("${skill.id}: ${skill.description}")
    }
    return 0
}

func cmdSkillsSearch(config: AppConfig, nonOptions: Array<String>): Int64 {
    let query = nonOptionAt(nonOptions, 1)
    if (query.isEmpty()) {
        eprintln("skills-search requires a query")
        return 1
    }
    let registry = SkillRegistry(config.serviceRoot)
    for (skill in registry.search(query, limit: 8)) {
        println("${skill.id}: ${skill.description}")
        println(skill.preview)
        println("")
    }
    return 0
}

func cmdExamples(config: AppConfig, _: Array<String>): Int64 {
    for (project in listExampleProjects(config.serviceRoot)) {
        println("${project.id}: ${project.description}")
    }
    return 0
}

func cmdBootstrapJsonParser(config: AppConfig, nonOptions: Array<String>): Int64 {
    let path = nonOptionAt(nonOptions, 1)
    if (path.isEmpty()) {
        eprintln("bootstrap-json-parser requires a target path")
        return 1
    }
    println(bootstrapJsonParserProject(config.serviceRoot, config.workspaceRoot, path))
    return 0
}

func cmdBootstrap(config: AppConfig, nonOptions: Array<String>): Int64 {
    let projectId = nonOptionAt(nonOptions, 1)
    let path = nonOptionAt(nonOptions, 2)
    if (projectId.isEmpty() || path.isEmpty()) {
        eprintln("bootstrap requires a project id and target path")
        eprintln("Available projects:")
        for (project in listExampleProjects(config.serviceRoot)) {
            eprintln("  ${project.id} - ${project.description}")
        }
        return 1
    }
    println(bootstrapExampleProject(config.serviceRoot, config.workspaceRoot, projectId, path))
    return 0
}

func cmdAnalyze(config: AppConfig, nonOptions: Array<String>): Int64 {
    let path = nonOptionAt(nonOptions, 1)
    if (path.isEmpty()) {
        eprintln("analyze requires a file path")
        return 1
    }
    let result = analyzeCangjieFile(config.workspaceRoot, path)
    println("[${result.engine}] ${result.summary}")
    println(result.output)
    return if (result.success) { 0 } else { 1 }
}

func cmdCreateFile(config: AppConfig, nonOptions: Array<String>): Int64 {
    let path = nonOptionAt(nonOptions, 1)
    if (path.isEmpty()) {
        eprintln("create-file requires a target path")
        return 1
    }
    let content = nonOptionAt(nonOptions, 2)
    println(workspaceCreateFileJson(config.workspaceRoot, path, content))
    return 0
}

func cmdLspStatus(config: AppConfig, _: Array<String>): Int64 {
    let status = inspectLspStatus(config.workspaceRoot)
    println(status.summary)
    if (!status.command.isEmpty()) {
        println("command: ${status.command}")
    }
    println(status.sourceHint)
    return if (status.available) { 0 } else { 1 }
}

func cmdLspProbe(config: AppConfig, _: Array<String>): Int64 {
    let result = probeLspServer(config.workspaceRoot)
    println(result.summary)
    if (!result.command.isEmpty()) {
        println("command: ${result.command}")
    }
    if (!result.responsePreview.trimAscii().isEmpty()) {
        println(result.responsePreview)
    }
    return if (result.success) { 0 } else { 1 }
}

func cmdLspDocumentSymbols(config: AppConfig, nonOptions: Array<String>): Int64 {
    let path = nonOptionAt(nonOptions, 1)
    if (path.isEmpty()) {
        eprintln("lsp-document-symbols requires a file path")
        return 1
    }
    return printLspQueryResult(queryLspDocumentSymbols(config.workspaceRoot, path))
}

func cmdLspWorkspaceSymbols(config: AppConfig, nonOptions: Array<String>): Int64 {
    let query = nonOptionAt(nonOptions, 1)
    return printLspQueryResult(queryLspWorkspaceSymbols(config.workspaceRoot, query))
}

func cmdLspDefinition(config: AppConfig, nonOptions: Array<String>): Int64 {
    let path = nonOptionAt(nonOptions, 1)
    let lineStr = nonOptionAt(nonOptions, 2)
    let colStr = nonOptionAt(nonOptions, 3)
    if (path.isEmpty() || lineStr.isEmpty() || colStr.isEmpty()) {
        eprintln("lsp-definition requires path, line, and column")
        return 1
    }
    return printLspQueryResult(queryLspDefinition(config.workspaceRoot,
        path,
        Int64.parse(lineStr),
        Int64.parse(colStr)))
}

func cmdHelp(_: AppConfig, _: Array<String>): Int64 {
    printUsage()
    return 0
}

// 构建 CLI 子命令名到处理函数的注册表
func buildSubcommandRegistry(): HashMap<String, CliSubcommandHandler> {
    let registry = HashMap<String, CliSubcommandHandler>()
    registry["mcp-stdio"] = cmdMcpStdio
    registry["skills"] = cmdSkills
    registry["skills-search"] = cmdSkillsSearch
    registry["examples"] = cmdExamples
    registry["bootstrap-json-parser"] = cmdBootstrapJsonParser
    registry["bootstrap"] = cmdBootstrap
    registry["analyze"] = cmdAnalyze
    registry["create-file"] = cmdCreateFile
    registry["lsp-status"] = cmdLspStatus
    registry["lsp-probe"] = cmdLspProbe
    registry["lsp-document-symbols"] = cmdLspDocumentSymbols
    registry["lsp-workspace-symbols"] = cmdLspWorkspaceSymbols
    registry["lsp-definition"] = cmdLspDefinition
    registry["help"] = cmdHelp
    return registry
}

main(args: Array<String>): Int64 {
    // 使用 std.argopt 统一管理全局选项，子命令通过 nonOptions 获取
    let specs: Array<ArgumentSpec> = [
        Full("help", r'h', NoValue),
        Full("version", r'V', NoValue),
        Full("repo", r'r', RequiredValue),
    ]

    var options = HashMap<String, String>()
    var nonOptions = Array<String>()
    try {
        let result = parseArguments(args, specs)
        for ((k, v) in result.options) {
            options[k] = v
        }
        nonOptions = result.nonOptions
    } catch (e: ArgumentParseException) {
        eprintln("参数解析错误: ${e}")
        printUsage()
        return 1
    }

    if (options.contains("help") || options.contains("h")) {
        printUsage()
        return 0
    }
    if (options.contains("version") || options.contains("V")) {
        println("CangjieCoder ${APP_VERSION}")
        return 0
    }
    if (nonOptions.isEmpty()) {
        printUsage()
        return 0
    }

    let config = buildAppConfig(options)
    let subcommand = nonOptions[0]
    let subcommandRegistry = buildSubcommandRegistry()

    match (subcommandRegistry.get(subcommand)) {
        case Some(handler) => return handler(config, nonOptions)
        case None =>
            eprintln("Unknown subcommand: ${subcommand}")
            printUsage()
            return 1
    }
}
