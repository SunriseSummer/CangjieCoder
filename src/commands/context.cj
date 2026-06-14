package cangjiecoder.commands

import cangjiecoder.config.*
import cangjiecoder.provider.*
import cangjiecoder.session.*
import cangjiecoder.agent.*
import cangjiecoder.tools.*

/**
 * REPL 共享上下文：在命令处理器与主循环之间传递状态
 *
 * 包括：
 *  - 配置 / 服务商 / 模型 / 会话
 *  - Coding Agent 模式开关 + agent loop 实例
 *  - 工具注册中心 + 审批器 + TODO 存储
 */

public enum InteractionMode {
    /** 纯聊天，流式输出，不调用工具 */
    | Chat
    /** Coding Agent 模式，多轮工具调用 */
    | Agent
}

public func modeName(m: InteractionMode): String {
    return match (m) {
        case Chat => "chat"
        case Agent => "agent"
    }
}

public class Context {
    public var config: AppConfig
    public var provider: ProviderPreset
    public var model: ModelPreset
    public var session: ChatSession
    public var mode: InteractionMode
    public var agent: AgentLoop
    public let approver: Approver
    public let registry: ToolRegistry
    public let todoStore: TodoStore
    public let journal: FileJournal
    public var baseSystemPrompt: String

    public init(
        config: AppConfig,
        provider: ProviderPreset,
        model: ModelPreset,
        session: ChatSession,
        agent: AgentLoop,
        approver: Approver,
        registry: ToolRegistry,
        todoStore: TodoStore,
        journal: FileJournal,
        baseSystemPrompt: String
    ) {
        this.config = config
        this.provider = provider
        this.model = model
        this.session = session
        this.mode = Agent
        this.agent = agent
        this.approver = approver
        this.registry = registry
        this.todoStore = todoStore
        this.journal = journal
        this.baseSystemPrompt = baseSystemPrompt
    }
}

/** 命令处理返回值`Exit` 表示主循环应退出 */
public enum CommandResult {
    | Continue
    | Exit
}
