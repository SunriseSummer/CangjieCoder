package cangjiecoderagent

// 打印命令行用法，保持入口文件只负责参数校验与调度，
// 具体的多轮规划/执行逻辑全部下沉到 runner 中。
func printUsage(): Unit {
    println("CangjieCoder Agent")
    println("")
    println("Usage:")
    println("  cangjiecoderagent providers")
    println("  cangjiecoderagent --workspace PATH --prompt TEXT [--service-dir PATH] [--provider kimi|glm|openrouter] [--model MODEL] [--max-rounds N]")
    println("")
    println("The agent drives ../service over stdio MCP, uses a bounded multi-round plan/act/review loop, and falls back to local heuristics when remote model access is unavailable.")
}

main(args: Array<String>): Int64 {
    if (args.size == 1 && args[0] == "providers") {
        println(listProvidersText())
        return 0
    }
    // main 只做最薄的一层封装：解析参数、校验 prompt，
    // 然后把完整执行流程交给 runAgent，便于后续继续演进架构。
    let config = parseConfig(args)
    if (config.prompt.trimAscii().isEmpty()) {
        printUsage()
        return 1
    }

    return runAgent(config)
}
