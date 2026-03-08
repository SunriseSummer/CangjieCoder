package cangjiecoderagent

func printUsage(): Unit {
    println("CangjieCoder Agent")
    println("")
    println("Usage:")
    println("  cangjiecoderagent --workspace PATH --prompt TEXT [--service-dir PATH] [--provider kimi|glm|openrouter] [--model MODEL] [--max-rounds N]")
    println("")
    println("The agent drives ../service over stdio MCP, uses a bounded multi-round plan/act/review loop, and falls back to local heuristics when remote model access is unavailable.")
}

main(args: Array<String>): Int64 {
    let config = parseConfig(args)
    if (config.prompt.trimAscii().isEmpty()) {
        printUsage()
        return 1
    }

    return runAgent(config)
}
