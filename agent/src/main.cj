package cangjiecoderagent

import cangjiecoderagent.common.*
import cangjiecoderagent.ai.*

// 打印命令行用法，列出子命令与全局选项
func printUsage(): Unit {
    println("CangjieCoder Agent")
    println("")
    println("Usage:")
    println("  cangjiecoderagent providers")
    println("  cangjiecoderagent [OPTIONS] --prompt TEXT")
    println("")
    println("Options:")
    println("  -h, --help              Show help message")
    println("  -w, --workspace PATH    Target workspace root")
    println("  -s, --service-dir PATH  Service binary directory")
    println("  --provider NAME         AI provider (kimi|glm|openrouter)")
    println("  -m, --model MODEL       Model name")
    println("  -n, --max-rounds N      Maximum planning rounds")
    println("  -p, --prompt TEXT       User prompt (remaining args are appended)")
    println("")
    println("The agent drives ../service over stdio MCP, uses a bounded multi-round plan/act/review loop, and falls back to local heuristics when remote model access is unavailable.")
}

main(args: Array<String>): Int64 {
    // providers 子命令是独立入口，直接返回
    if (args.size == 1 && args[0] == "providers") {
        println(listProvidersText())
        return 0
    }
    // parseConfig 内部使用 std.argopt 解析参数，
    // --help 时返回空 prompt，由此处统一显示用法
    let config = parseConfig(args)
    if (config.prompt.trimAscii().isEmpty()) {
        printUsage()
        return if (args.isEmpty()) { 0 } else { 1 }
    }

    return runAgent(config)
}
