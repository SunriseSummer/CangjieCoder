package cangjiecoderagent

import std.collection.*
import stdx.encoding.json.*

func mergedPlanSummary(plans: Array<AgentPlan>): String {
    let summaries = ArrayList<String>()
    for (plan in plans) {
        if (!plan.summary.trimAscii().isEmpty()) {
            summaries.add(plan.summary)
        }
    }
    return if (summaries.isEmpty()) { "No plan summary" } else { String.join(summaries.toArray(), delimiter: " -> ") }
}

func stepSignature(tool: String, arguments: JsonObject): String {
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
    // Follow-up rounds are reserved for incomplete or unstable outcomes; a fully
    // successful round exits early to keep the agent bounded and predictable.
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
    let workspaceSnapshot = client.callTool("workspace.list_files", JsonObject()).toString()
    let exampleProjects = client.callTool("project.list_examples", JsonObject()).toString()
    return AgentPlanningContext(config.prompt, toolsJson, workspaceSnapshot, exampleProjects)
}

func printRoundPlan(round: Int64, plan: AgentPlan, steps: Array<PlannedToolCall>): Unit {
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
    let sessionId = client.startConversationSession()

    let executions = ArrayList<ToolExecution>()
    let plans = ArrayList<AgentPlan>()
    var allOk = true
    var round: Int64 = 0
    while (round < config.maxRounds) {
        // Refresh workspace state on every round so replanning sees mutations from
        // previous tool calls instead of relying on stale snapshots.
        let context = planningContext(client, config, toolsJson)
        let planTurn = if (round == 0) {
            client.conversationTurn(buildPlanPrompt(context), sessionId: sessionId)
        } else {
            client.conversationTurn(buildReplanPrompt(config.prompt, plans.toArray(), executions.toArray(), context), sessionId: sessionId)
        }
        let plan = parsePlan(planTurn.reply, context)
        plans.add(plan)

        // Validation steps are appended before duplicate filtering so automatic
        // build/test checks still participate in the same deduplication rules.
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
    let remoteFinalTurn = client.conversationTurn(buildFinalPrompt(config.prompt, finalPlan, executions.toArray()), sessionId: sessionId)
    // Final summarization degrades to a local transcript when the provider is
    // unavailable so the agent still returns a useful deterministic result.
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
