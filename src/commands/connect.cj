package cangjiecoder.commands

import cangjiecoder.config.*
import cangjiecoder.provider.*
import std.convert.*

/**
 * `/connect` — 切换服务商并设置/确认 API Key
 *
 * 用法：
 *   /connect             列出所有服务商并交互式选择
 *   /connect huawei      直接切换并提示输入 API Key（若未配置）
 */

public func handleConnect(arg: String, ctx: Context): CommandResult {
    let trimmed = arg.trimAscii()
    if (trimmed.isEmpty()) {
        return interactiveConnect(ctx)
    }
    return connectTo(trimmed, ctx)
}

func interactiveConnect(ctx: Context): CommandResult {
    println("请选择服务商: ")
    let providers = allProviders()
    for (i in 0..providers.size) {
        let provider = providers[i]
        let mark = if (provider.id == ctx.provider.id) { " *" } else { "  " }
        println("  ${i + 1}.${mark} ${provider.id.padEnd(10)}  ${provider.displayName}")
    }
    print("输入序号或服务商 ID > ", flush: true)
    let line = readln().trimAscii()
    if (line.isEmpty()) {
        println("已取消")
        return Continue
    }
    var targetId = line
    match (Int64.tryParse(line)) {
        case Some(idx) where idx >= 1 && idx <= providers.size =>
            targetId = providers[idx - 1].id
        case _ => ()
    }
    return connectTo(targetId, ctx)
}

func connectTo(providerId: String, ctx: Context): CommandResult {
    let prov = match (findProvider(providerId)) {
        case Some(found) => found
        case None =>
            eprintln("未知服务商: ${providerId}")
            return Continue
    }
    let cred = ctx.config.getCredential(prov.id)
    let existingKey = match (cred) {
        case Some(credential) => credential.apiKey
        case None => ""
    }
    var endpoint = match (cred) {
        case Some(credential) where !credential.endpoint.isEmpty() => credential.endpoint
        case _ => prov.defaultEndpoint
    }

    // 自定义服务商需要先配置 BaseURL
    if (prov.id == "custom") {
        if (endpoint.isEmpty()) {
            print("请输入 OpenAI 兼容接口 BaseURL > ", flush: true)
        } else {
            print("已设置 BaseURL: ${endpoint}，直接回车确认使用，或输入新地址覆盖 > ", flush: true)
        }
        let urlInput = readln().trimAscii()
        if (!urlInput.isEmpty()) {
            endpoint = urlInput
        }
        if (endpoint.isEmpty()) {
            eprintln("未提供 BaseURL，已取消切换服务商")
            return Continue
        }
    }

    if (existingKey.isEmpty()) {
        print("请输入 ${prov.displayName} 的 API Key > ", flush: true)
    } else {
        print("已设置 API Key，直接回车确认使用，或输入新 API Key 覆盖 > ", flush: true)
    }
    let input = readln().trimAscii()
    let apiKey = if (input.isEmpty()) { existingKey } else { input }
    if (apiKey.isEmpty()) {
        eprintln("未提供 API Key，已取消切换服务商")
        return Continue
    }
    ctx.config.setCredential(prov.id, apiKey, endpoint)
    ctx.config.currentProvider = prov.id
    ctx.provider = prov
    ctx.model = prov.defaultModel()
    ctx.config.currentModel = ctx.model.id
    ctx.session.endpoint = endpoint
    ctx.session.apiKey = apiKey
    ctx.session.model = ctx.model.id
    ctx.session.clearHistory()
    ctx.agent.endpoint = endpoint
    ctx.agent.apiKey = apiKey
    ctx.agent.model = ctx.model.id
    ctx.agent.clearHistory()
    saveConfig(ctx.config)
    println("已切换到 ${prov.displayName}，默认模型: ${ctx.model.displayName} (${ctx.model.id})")
    return Continue
}
