package cangjiecoderagent

import std.collection.*
import std.convert.*
import std.env.*
import std.fs.*
import stdx.encoding.json.*

const DEFAULT_PROVIDER: String = "kimi"
const DEFAULT_MODEL: String = "kimi-k2.5"
const DEFAULT_MAX_ROUNDS: Int64 = 2
// MAX_PLAN_STEPS is intentionally 6 so a single bounded plan can fit up to six
// steps and still accommodate inspect + read-config + analyze + mutate + build + test workflows.
const MAX_PLAN_STEPS: Int64 = 6
const MAX_TRANSCRIPT_LINES: Int64 = 12

struct AgentConfig {
    public AgentConfig(let workspaceRoot: String,
                       let serviceDir: String,
                       let provider: String,
                       let model: String,
                       let maxRounds: Int64,
                       let prompt: String) {}
}

struct PlannedToolCall {
    public PlannedToolCall(let tool: String,
                           let arguments: JsonObject,
                           let reason: String) {}
}

struct AgentPlan {
    public AgentPlan(let summary: String,
                     let steps: Array<PlannedToolCall>) {}
}

struct ToolExecution {
    public ToolExecution(let tool: String,
                         let arguments: JsonObject,
                         let ok: Bool,
                         let summary: String,
                         let preview: String) {}
}

struct ModelTurn {
    public ModelTurn(let reply: String,
                     let sessionId: String,
                     let success: Bool) {}
}

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
    if (body.trimAscii().isEmpty()) {
        return JsonObject()
    }
    return JsonValue.fromStr(body).asObject()
}

func shortPreview(text: String, maxLines!: Int64 = 8): String {
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
    return "'${text.replace("'", "'\"'\"'")}'"
}

func extractStructuredData(result: JsonObject): JsonObject {
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
    for (candidate in candidates) {
        if (text.contains(candidate)) {
            return true
        }
    }
    return false
}
