package cangjiecoder.app

import std.collection.*
import std.env.*
import cangjiecoder.config.*
import cangjiecoder.provider.*
import cangjiecoder.session.*
import cangjiecoder.skillset.*
import cangjiecoder.httpx.*
import cangjiecoder.tools.*
import cangjiecoder.agent.*
import cangjiecoder.commands.*

/**
 * 引导：加载配置、构造 chat session + agent loop + tool registry，
 * 注入项目 Skills 与上下文
 *
 * 若用户尚未配置 API Key，则进入 `/connect` 引导流程
 */

public let DEFAULT_BASE_PROMPT: String =
    "请用中文回答；回答简洁、专业、严谨；涉及代码时给出完整可运行示例并解释关键设计决策。"

public func bootstrap(): ?Context {
    let cfg = loadConfig()
    if (cfg.systemPrompt.isEmpty()) {
        cfg.systemPrompt = DEFAULT_BASE_PROMPT
    }
    let provider = resolveProvider(cfg)
    let model = resolveModel(provider, cfg)
    let (apiKey, endpoint) = resolveCredential(provider, cfg)

    // Skills 按需加载：初始化时仅读取 name + description
    let cwd = getWorkingDirectory()
    let skillSummaries = discoverSkillSummaries(cwd)

    let todoStore = TodoStore()
    let journal = FileJournal()
    let registry = defaultRegistry(todoStore, journal, skillSummaries)
    let approver = Approver(Default_)

    let chatPrompt = composeChatPrompt(cfg.systemPrompt, skillSummaries)
    let agentPrompt = buildAgentSystemPrompt(chatPrompt, registry)

    let client = ChatClient()
    let session = ChatSession(endpoint, apiKey, model.id, systemPrompt: chatPrompt,
                              client: client)
    let agent = AgentLoop(client, registry, approver, endpoint, apiKey, model.id, agentPrompt)

    let ctx = Context(cfg, provider, model, session, agent, approver, registry, todoStore,
                      journal, cfg.systemPrompt)

    if (apiKey.isEmpty()) {
        println("尚未配置 ${provider.displayName} 的 API Key。")
        handleConnect("", ctx)
        if (ctx.session.apiKey.isEmpty()) {
            eprintln("未提供 API Key，已退出。")
            return None
        }
    }
    cfg.currentProvider = provider.id
    cfg.currentModel = model.id
    saveConfig(cfg)
    return Some(ctx)
}

func resolveCredential(provider: ProviderPreset, cfg: AppConfig): (String, String) {
    match (cfg.getCredential(provider.id)) {
        case Some(c) =>
            let ep = if (c.endpoint.isEmpty()) { provider.defaultEndpoint } else { c.endpoint }
            return (c.apiKey, ep)
        case None => return ("", provider.defaultEndpoint)
    }
}

func resolveProvider(cfg: AppConfig): ProviderPreset {
    // 1) 若当前服务商已配置 API Key，优先沿用
    if (!cfg.currentProvider.isEmpty()) {
        match (findProvider(cfg.currentProvider)) {
            case Some(p) where providerHasKey(cfg, p.id) => return p
            case _ => ()
        }
    }
    // 2) 当前服务商无 Key：若其它服务商已配置 Key，自动切换到第一个可用者，
    //    从而跳过服务商选择直接进入主程序
    match (firstProviderWithKey(cfg)) {
        case Some(p) => return p
        case None => ()
    }
    // 3) 无任何可用 Key：回退到当前服务商（若有）或默认服务商
    if (!cfg.currentProvider.isEmpty()) {
        match (findProvider(cfg.currentProvider)) {
            case Some(p) => return p
            case None => ()
        }
    }
    return defaultProvider()
}

func providerHasKey(cfg: AppConfig, providerId: String): Bool {
    match (cfg.getCredential(providerId)) {
        case Some(c) => return !c.apiKey.isEmpty()
        case None => return false
    }
}

func firstProviderWithKey(cfg: AppConfig): ?ProviderPreset {
    // 按内建服务商顺序选择，保证启动结果确定
    for (p in allProviders()) {
        if (providerHasKey(cfg, p.id)) {
            return p
        }
    }
    return None
}

func resolveModel(provider: ProviderPreset, cfg: AppConfig): ModelPreset {
    if (!cfg.currentModel.isEmpty()) {
        match (provider.findModel(cfg.currentModel)) {
            case Some(m) => return m
            case None => ()
        }
    }
    return provider.defaultModel()
}

func composeChatPrompt(base: String, summaries: ArrayList<SkillSummary>): String {
    let extra = renderSkillCatalog(summaries)
    if (extra.isEmpty()) {
        return base
    }
    if (base.isEmpty()) {
        return extra
    }
    return base + "\n\n" + extra
}


