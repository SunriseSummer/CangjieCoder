package cangjiecoderagent

import std.collection.*
import std.convert.*
import std.env.*
import std.fs.*
import stdx.encoding.json.*

const DEFAULT_PROVIDER: String = "kimi"
const DEFAULT_MODEL: String = "kimi-k2.5"
const DEFAULT_MAX_ROUNDS: Int64 = 2
// 将单轮计划上限限制为 6，既能覆盖“查看 -> 读配置 -> 分析 -> 修改 ->
// 构建 -> 测试”的常见闭环，又能避免模型一次输出过长计划导致执行发散。
const MAX_PLAN_STEPS: Int64 = 6
const MAX_TRANSCRIPT_LINES: Int64 = 12

// AgentConfig 汇总一次运行所需的全部外部输入，
// 让后续模块尽量只依赖结构化配置而不是分散的命令行参数。
struct AgentConfig {
    public AgentConfig(let workspaceRoot: String,
                       let serviceDir: String,
                       let provider: String,
                       let model: String,
                       let maxRounds: Int64,
                       let prompt: String) {}
}

// PlannedToolCall 表示规划阶段产出的单个 MCP 工具调用，
// 其中保留 reason，便于打印计划和在 replanning 时回溯上下文。
struct PlannedToolCall {
    public PlannedToolCall(let tool: String,
                           let arguments: JsonObject,
                           let reason: String) {}
}

// AgentPlan 是一轮规划的摘要与步骤集合。
struct AgentPlan {
    public AgentPlan(let summary: String,
                     let steps: Array<PlannedToolCall>) {}
}

// ToolExecution 保存实际执行结果，既用于最终总结，
// 也用于下一轮 replanning 时判断是否需要补充动作。
struct ToolExecution {
    public ToolExecution(let tool: String,
                         let arguments: JsonObject,
                         let ok: Bool,
                         let summary: String,
                         let preview: String) {}
}

// ModelTurn 统一封装一次模型对话的返回，显式记录 sessionId 与 success，
// 这样在 provider 降级或会话续传时不需要依赖隐式约定。
struct ModelTurn {
    public ModelTurn(let reply: String,
                     let sessionId: String,
                     let success: Bool) {}
}

// AgentPlanningContext 收集规划阶段会用到的外部上下文快照，
// 避免 planner 直接访问客户端，方便测试与本地回退逻辑复用。
struct AgentPlanningContext {
    public AgentPlanningContext(let userPrompt: String,
                                let toolsJson: String,
                                let workspaceSnapshot: String,
                                let exampleProjectsJson: String) {}
}

func parseConfig(args: Array<String>): AgentConfig {
    var workspaceRoot = canonicalize(getWorkingDirectory().toString()).toString()
    var serviceDir = resolveDefaultServiceDir(workspaceRoot)
    var serviceDirExplicit = false
    var provider = DEFAULT_PROVIDER
    var model = DEFAULT_MODEL
    var maxRounds = DEFAULT_MAX_ROUNDS
    var prompt = ""
    var index = 0
    while (index < args.size) {
        let current = args[index]
        if (current == "--workspace" && index + 1 < args.size) {
            workspaceRoot = canonicalize(args[index + 1]).toString()
            index += 1
        } else if (current == "--service-dir" && index + 1 < args.size) {
            serviceDir = canonicalize(args[index + 1]).toString()
            serviceDirExplicit = true
            index += 1
        } else if (current == "--provider" && index + 1 < args.size) {
            provider = args[index + 1]
            index += 1
        } else if (current == "--model" && index + 1 < args.size) {
            model = args[index + 1]
            index += 1
        } else if (current == "--max-rounds" && index + 1 < args.size) {
            maxRounds = Int64.parse(args[index + 1])
            index += 1
        } else if (current == "--prompt" && index + 1 < args.size) {
            let promptParts = ArrayList<String>()
            var promptIndex = index + 1
            // prompt 放在最后并吞掉剩余参数，允许用户直接输入自然语言，
            // 不必在 shell 中额外处理复杂空格或中英文混合内容。
            while (promptIndex < args.size) {
                promptParts.add(args[promptIndex])
                promptIndex += 1
            }
            prompt = String.join(promptParts.toArray(), delimiter: " ")
            break
        }
        index += 1
    }
    if (!serviceDirExplicit) {
        serviceDir = resolveDefaultServiceDir(workspaceRoot)
    }
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

func jsonField(obj: JsonObject, key: String, fallback!: String = ""): String {
    match (obj.get(key)) {
        case Some(value) =>
            match (value.kind()) {
                case JsString => return value.asString().getValue()
                case _ => return value.toString()
            }
        case None => return fallback
    }
}

func parseJsonObject(body: String): JsonObject {
    // 统一把空文本视为 {}，减少上层调用中的空串判定分支。
    if (body.trimAscii().isEmpty()) {
        return JsonObject()
    }
    return JsonValue.fromStr(body).asObject()
}

func shortPreview(text: String, maxLines!: Int64 = 8): String {
    // 预览摘要会跳过空行，只保留前若干条有效输出，
    // 这样控制台和最终总结都能保持紧凑可读。
    let lines = ArrayList<String>()
    var count: Int64 = 0
    for (line in text.lines()) {
        if (line.trimAscii().isEmpty()) {
            continue
        }
        lines.add(line)
        count += 1
        if (count >= maxLines) {
            break
        }
    }
    return String.join(lines.toArray(), delimiter: "\n")
}

func shellQuote(text: String): String {
    // 采用最保守的单引号转义策略，避免把路径/提示词直接拼入 shell
    // 时因为特殊字符破坏命令结构。
    return "'${text.replace("'", "'\"'\"'")}'"
}

func extractStructuredData(result: JsonObject): JsonObject {
    // service 侧会把结构化结果编码进 data 字段，这里统一解包，
    // 让 planner / executor 可以用一致的数据视图继续处理。
    return parseJsonObject(jsonField(result, "data", fallback: "{}"))
}

func jsonArrayStrings(array: JsonArray): Array<String> {
    let items = ArrayList<String>()
    var index: Int64 = 0
    while (index < array.size()) {
        match (array.get(index)) {
            case Some(value) =>
                match (value.kind()) {
                    case JsString => items.add(value.asString().getValue())
                    case _ => items.add(value.toString())
                }
            case None => ()
        }
        index += 1
    }
    return items.toArray()
}

func containsAny(text: String, candidates: Array<String>): Bool {
    // 统一封装中英文关键字匹配，便于 planner 在本地回退时复用同一组启发式。
    for (candidate in candidates) {
        if (text.contains(candidate)) {
            return true
        }
    }
    return false
}
