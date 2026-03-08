package cangjiecoderagent

import std.collection.*
import stdx.encoding.json.*

func printUsage(): Unit {
    println("CangjieCoder Agent")
    println("")
    println("Usage:")
    println("  cangjiecoderagent --workspace PATH --prompt TEXT [--service-dir PATH] [--provider kimi|glm] [--model MODEL]")
    println("")
    println("The agent drives ../service over stdio MCP, prefers model planning, and falls back to local heuristics when remote model access is unavailable.")
}

main(args: Array<String>): Int64 {
    let config = parseConfig(args)
    if (config.prompt.trimAscii().isEmpty()) {
        printUsage()
        return 1
    }

    let client = ServiceClient(config)
    let toolsJson = client.listToolsJson()
    let workspaceSnapshot = client.callTool("workspace.list_files", JsonObject()).toString()
    let exampleProjects = client.callTool("project.list_examples", JsonObject()).toString()
    let planningContext = AgentPlanningContext(config.prompt, toolsJson, workspaceSnapshot, exampleProjects)
    let planReply = client.conversationReply(buildPlanPrompt(planningContext))
    let parsedPlan = parsePlan(planReply, planningContext)
    let steps = appendValidationSteps(parsedPlan.steps, allowedTools: allowedToolNames(toolsJson))

    println("[plan]")
    println(parsedPlan.summary)
    for (step in steps) {
        println("- ${step.tool}: ${step.reason}")
    }

    let executions = ArrayList<ToolExecution>()
    var allOk = true
    for (step in steps) {
        let result = client.callTool(step.tool, step.arguments)
        let execution = formatExecution(result, step.tool)
        executions.add(execution)
        println("[tool] ${execution.tool} => ${execution.summary}")
        if (!execution.preview.trimAscii().isEmpty()) {
            println(execution.preview)
        }
        if (!execution.ok) {
            allOk = false
        }
    }

    let remoteFinalReply = client.conversationReply(buildFinalPrompt(config.prompt, parsedPlan, executions.toArray()))
    let finalReply = if (remoteFinalReply.startsWith("Provider request failed:") ||
        remoteFinalReply.startsWith("Missing API key:") ||
        remoteFinalReply.startsWith("Unsupported provider:")) {
        buildLocalFinalSummary(parsedPlan, executions.toArray())
    } else {
        remoteFinalReply
    }
    println("\n[final]\n${finalReply}")
    return if (allOk) { 0 } else { 1 }
}
