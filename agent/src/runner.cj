package cangjiecoderagent

import std.collection.*
import stdx.encoding.json.*

func mergedPlanSummary(plans: Array<AgentPlan>): String {
    // 多轮执行结束后，把每轮摘要串起来，便于最终总结同时保留 replanning 痕迹。
    let summaries = ArrayList<String>()
    for (plan in plans) {
        if (!plan.summary.trimAscii().isEmpty()) {
            summaries.add(plan.summary)
        }
    }
    return if (summaries.isEmpty()) { "No plan summary" } else { String.join(summaries.toArray(), delimiter: " -> ") }
}

func stepSignature(tool: String, arguments: JsonObject): String {
    // 使用“工具名 + 序列化参数”作为幂等签名，
    // 用最小代价屏蔽模型在多轮中重复给出相同步骤。
    return "${tool.trimAscii()}|${arguments.toString()}"
}

func filterPendingSteps(steps: Array<PlannedToolCall>, executions: Array<ToolExecution>): Array<PlannedToolCall> {
    let executed = HashSet<String>()
    for (execution in executions) {
        executed.add(stepSignature(execution.tool, execution.arguments))
    }
    let results = ArrayList<PlannedToolCall>()
    for (step in steps) {
        let signature = stepSignature(step.tool, step.arguments)
        if (executed.contains(signature)) {
            continue
        }
        results.add(step)
    }
    return results.toArray()
}

func hasExecutionFailure(executions: Array<ToolExecution>): Bool {
    for (execution in executions) {
        if (!execution.ok) {
            return true
        }
    }
    return false
}

func hasMutatingExecution(executions: Array<ToolExecution>): Bool {
    for (execution in executions) {
        if (isMutatingTool(execution.tool)) {
            return true
        }
    }
    return false
}

func hasVerificationExecution(executions: Array<ToolExecution>): Bool {
    for (execution in executions) {
        if (execution.tool == "workspace.run_build" || execution.tool == "workspace.run_test") {
            return true
        }
    }
    return false
}

func roundWasInspectionOnly(executions: Array<ToolExecution>): Bool {
    // 纯检查轮次意味着模型还停留在“观察阶段”，
    // 若用户明确要求修改或验证，下一轮通常仍应继续推进。
    if (executions.isEmpty()) {
        return false
    }
    for (execution in executions) {
        let tool = execution.tool
        if (isMutatingTool(tool) || tool == "workspace.run_build" || tool == "workspace.run_test") {
            return false
        }
    }
    return true
}

func shouldTriggerFollowUpRound(prompt: String,
                                roundExecutions: Array<ToolExecution>,
                                allExecutions: Array<ToolExecution>,
                                currentRound: Int64,
                                maxRounds: Int64): Bool {
    // 追加轮次只留给“失败、未验证、只观察未落地”这几类不完整结果；
    // 一旦当前结果已经稳定，就立即收敛，保证 agent 有界且可预测。
    if (currentRound + 1 >= maxRounds || roundExecutions.isEmpty()) {
        return false
    }
    if (hasExecutionFailure(roundExecutions)) {
        return true
    }
    if (promptNeedsVerification(prompt) && !hasVerificationExecution(allExecutions)) {
        return true
    }
    if (promptNeedsMutation(prompt) && !hasMutatingExecution(allExecutions) && roundWasInspectionOnly(roundExecutions)) {
        return true
    }
    return false
}

func planningContext(client: ServiceClient, config: AgentConfig, toolsJson: String): AgentPlanningContext {
    // 每轮都重新抓取工作区快照与 example 列表，
    // 避免 bootstrap / 编辑之后继续拿旧状态做规划。
    let workspaceSnapshot = client.callTool("workspace.list_files", JsonObject()).toString()
    let exampleProjects = client.callTool("project.list_examples", JsonObject()).toString()
    return AgentPlanningContext(config.prompt, toolsJson, workspaceSnapshot, exampleProjects)
}

func printRoundPlan(round: Int64, plan: AgentPlan, steps: Array<PlannedToolCall>): Unit {
    // 控制台计划输出保持简单直接，便于人工观察 agent 每轮决策。
    println("[plan round ${round}]")
    println(plan.summary)
    for (step in steps) {
        println("- ${step.tool}: ${step.reason}")
    }
}

func runAgent(config: AgentConfig): Int64 {
    let client = ServiceClient(config)
    let toolsJson = client.listToolsJson()
    let allowedTools = allowedToolNames(toolsJson)
    let conversations = ConversationStore()
    let sessionId = conversations.createSession().sessionId

    let executions = ArrayList<ToolExecution>()
    let plans = ArrayList<AgentPlan>()
    var allOk = true
    var round: Int64 = 0
    while (round < config.maxRounds) {
        /* 每轮都刷新工作区状态，让 replanning 能看到前一轮真实修改结果，
         * 而不是基于过期快照继续做错误决策。
         */
        let context = planningContext(client, config, toolsJson)
        let planTurn = if (round == 0) {
            conversationTurn(conversations,
                config.provider,
                config.model,
                planningSystemPrompt(),
                buildPlanPrompt(context),
                sessionId)
        } else {
            conversationTurn(conversations,
                config.provider,
                config.model,
                planningSystemPrompt(),
                buildReplanPrompt(config.prompt, plans.toArray(), executions.toArray(), context),
                sessionId)
        }
        let plan = parsePlan(planTurn.reply, context)
        plans.add(plan)

        // 先补自动验证步骤，再统一去重，这样补出来的 build/test
        // 也会遵守与模型原始步骤完全一致的幂等规则。
        let steps = filterPendingSteps(appendValidationSteps(plan.steps, allowedTools: allowedTools), executions.toArray())
        printRoundPlan(round + 1, plan, steps)
        if (steps.isEmpty()) {
            break
        }

        let roundExecutions = ArrayList<ToolExecution>()
        for (step in steps) {
            let result = client.callTool(step.tool, step.arguments)
            let execution = formatExecution(result, step.tool, step.arguments)
            executions.add(execution)
            roundExecutions.add(execution)
            println("[tool] ${execution.tool} => ${execution.summary}")
            if (!execution.preview.trimAscii().isEmpty()) {
                println(execution.preview)
            }
            if (!execution.ok) {
                allOk = false
            }
        }

        if (!shouldTriggerFollowUpRound(config.prompt, roundExecutions.toArray(), executions.toArray(), round, config.maxRounds)) {
            break
        }
        round += 1
    }

    let finalPlan = AgentPlan(mergedPlanSummary(plans.toArray()), [])
    let remoteFinalTurn = conversationTurn(conversations,
        config.provider,
        config.model,
        reportingSystemPrompt(),
        buildFinalPrompt(config.prompt, finalPlan, executions.toArray()),
        sessionId)
    // provider 不可用时退化到本地摘要，避免“工具执行成功但最后一句话没生成”
    // 这种体验断裂，保证用户始终能拿到确定性的最终结果。
    let finalReply = if (!remoteFinalTurn.success ||
        remoteFinalTurn.reply.startsWith("Provider request failed:") ||
        remoteFinalTurn.reply.startsWith("Missing API key:") ||
        remoteFinalTurn.reply.startsWith("Unsupported provider:")) {
        buildLocalFinalSummary(finalPlan, executions.toArray())
    } else {
        remoteFinalTurn.reply
    }
    println("\n[final]\n${finalReply}")
    return if (allOk) { 0 } else { 1 }
}
