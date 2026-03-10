package cangjiecoderagent

import std.argopt.*
import std.collection.*
import std.convert.*
import std.env.*
import std.fs.*
import cangjiecoderagent.common.*

const DEFAULT_PROVIDER: String = "kimi"
const DEFAULT_MODEL: String = "kimi-k2.5"
const DEFAULT_MAX_ROUNDS: Int64 = 2
const MAX_TRANSCRIPT_LINES: Int64 = 12

// Full 选项使用 --long 或 -s 形式时 key 不同，统一查找
func agentOptionValue(options: HashMap<String, String>, longKey: String, shortKey: String, fallback!: String = ""): String {
    return options.get(longKey) ?? options.get(shortKey) ?? fallback
}

// 使用 std.argopt 统一管理 Agent CLI 选项
func parseConfig(args: Array<String>): AgentConfig {
    let cwd = canonicalize(getWorkingDirectory().toString()).toString()
    let defaultServiceDir = resolveDefaultServiceDir(cwd)

    let specs: Array<ArgumentSpec> = [
        Full("help", r'h', NoValue),
        Full("workspace", r'w', RequiredValue),
        Full("service-dir", r's', RequiredValue),
        Long("provider", RequiredValue),
        Full("model", r'm', RequiredValue),
        Full("max-rounds", r'n', RequiredValue),
        Full("prompt", r'p', RequiredValue),
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
        return AgentConfig(cwd, defaultServiceDir, DEFAULT_PROVIDER, DEFAULT_MODEL, DEFAULT_MAX_ROUNDS, "")
    }

    // --help 或 -h 返回空 prompt，由上层显示用法
    if (options.contains("help") || options.contains("h")) {
        return AgentConfig(cwd, defaultServiceDir, DEFAULT_PROVIDER, DEFAULT_MODEL, DEFAULT_MAX_ROUNDS, "")
    }

    // Full 选项通过 --long 或 -s 设置的 key 不同，需同时检查长短名
    let workspaceRoot = canonicalize(agentOptionValue(options, "workspace", "w", fallback: cwd)).toString()
    let serviceDirOption = agentOptionValue(options, "service-dir", "s").trimAscii()
    let serviceDir = if (serviceDirOption.isEmpty()) {
        resolveDefaultServiceDir(workspaceRoot)
    } else {
        canonicalize(serviceDirOption).toString()
    }
    let provider = options.get("provider") ?? DEFAULT_PROVIDER
    let model = agentOptionValue(options, "model", "m", fallback: DEFAULT_MODEL)

    var maxRounds = DEFAULT_MAX_ROUNDS
    let maxRoundsStr = agentOptionValue(options, "max-rounds", "n").trimAscii()
    if (!maxRoundsStr.isEmpty()) {
        try {
            maxRounds = Int64.parse(maxRoundsStr)
        } catch (e: Exception) {
            maxRounds = DEFAULT_MAX_ROUNDS
        }
    }

    // --prompt 的值与剩余非选项参数合并为完整提示词，
    // 兼容不加引号的多词输入如 --prompt 请 创建 JsonParser 示例项目
    let promptParts = ArrayList<String>()
    let promptOption = agentOptionValue(options, "prompt", "p").trimAscii()
    if (!promptOption.isEmpty()) {
        promptParts.add(promptOption)
    }
    for (arg in nonOptions) {
        promptParts.add(arg)
    }
    let prompt = String.join(promptParts.toArray(), delimiter: " ")

    let normalizedMaxRounds = if (maxRounds < 1) { 1 } else { maxRounds }
    return AgentConfig(workspaceRoot, serviceDir, provider, model, normalizedMaxRounds, prompt)
}

func resolveDefaultServiceDir(workspaceRoot: String): String {
    // 优先兼容 monorepo 根目录下直接存在 service/ 的场景；
    // 如果 agent 在子目录独立运行，再回退到 ../service。
    let directServiceDir = "${workspaceRoot}/service"
    if (exists(directServiceDir)) {
        return canonicalize(directServiceDir).toString()
    }

    let parentServiceDir = "${workspaceRoot}/../service"
    if (exists(parentServiceDir)) {
        return canonicalize(parentServiceDir).toString()
    }
    return directServiceDir
}

