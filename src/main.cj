package cangjiecoder

func printUsage(): Unit {
    println("CangjieCoder - lightweight AI coding tool for Cangjie projects")
    println("")
    println("Usage:")
    println("  cangjiecoder serve [--repo PATH] [--host HOST] [--port PORT]")
    println("  cangjiecoder mcp-stdio [--repo PATH]")
    println("  cangjiecoder skills [--repo PATH]")
    println("  cangjiecoder skills-search <query> [--repo PATH]")
    println("  cangjiecoder examples [--repo PATH]")
    println("  cangjiecoder bootstrap-json-parser <path> [--repo PATH]")
    println("  cangjiecoder providers")
    println("  cangjiecoder analyze <path> [--repo PATH]")
    println("  cangjiecoder lsp-status [--repo PATH]")
    println("  cangjiecoder lsp-probe [--repo PATH]")
    println("")
    println("Environment:")
    println("  STDX_PATH            stdx binary dependency directory")
    println("  KIMI_API_KEY         API key for Kimi / Moonshot")
    println("  GLM_API_KEY          API key for GLM / Zhipu")
    println("  TREE_SITTER_CANGJIE  tree-sitter command with Cangjie grammar support")
    println("  CJLINT_COMMAND       override cjlint command")
    println("  CJC_COMMAND          override cjc command")
    println("  CANGJIE_LSP_COMMAND  explicit path/command for the Cangjie LSP binary")
    println("  CANGJIE_SDK_HOME     SDK home used to auto-discover tools/bin/LSPServer")
}

main(args: Array<String>): Int64 {
    if (args.isEmpty()) {
        printUsage()
        return 0
    }

    let config = parseConfig(args)
    match (args[0]) {
        case "serve" =>
            startServer(config)
            return 0
        case "mcp-stdio" =>
            startMcpStdioServer(config)
            return 0
        case "skills" =>
            let registry = SkillRegistry(config.repoRoot)
            for (skill in registry.list(limit: 200)) {
                println("${skill.id}: ${skill.description}")
            }
            return 0
        case "skills-search" =>
            if (args.size < 2) {
                eprintln("skills-search requires a query")
                return 1
            }
            let registry = SkillRegistry(config.repoRoot)
            for (skill in registry.search(args[1], limit: 8)) {
                println("${skill.id}: ${skill.description}")
                println(skill.preview)
                println("")
            }
            return 0
        case "providers" =>
            println(listProvidersText())
            return 0
        case "examples" =>
            for (project in listExampleProjects(config.repoRoot)) {
                println("${project.id}: ${project.description}")
            }
            return 0
        case "bootstrap-json-parser" =>
            if (args.size < 2) {
                eprintln("bootstrap-json-parser requires a target path")
                return 1
            }
            println(bootstrapJsonParserProject(config.repoRoot, args[1]))
            return 0
        case "analyze" =>
            if (args.size < 2) {
                eprintln("analyze requires a file path")
                return 1
            }
            let result = analyzeCangjieFile(config.repoRoot, args[1])
            println("[${result.engine}] ${result.summary}")
            println(result.output)
            return if (result.success) { 0 } else { 1 }
        case "lsp-status" =>
            let status = inspectLspStatus(config.repoRoot)
            println(status.summary)
            if (!status.command.isEmpty()) {
                println("command: ${status.command}")
            }
            println(status.sourceHint)
            return if (status.available) { 0 } else { 1 }
        case "lsp-probe" =>
            let result = probeLspServer(config.repoRoot)
            println(result.summary)
            if (!result.command.isEmpty()) {
                println("command: ${result.command}")
            }
            if (!result.responsePreview.trimAscii().isEmpty()) {
                println(result.responsePreview)
            }
            return if (result.success) { 0 } else { 1 }
        case "help" =>
            printUsage()
            return 0
        case _ =>
            printUsage()
            return 1
    }
}
