// 共享类型定义：Agent 各模块使用的核心数据结构
package cangjiecoderagent.common

import stdx.encoding.json.*

// 单轮计划上限限制为 6，既能覆盖"查看 → 读配置 → 分析 → 修改 → 构建 → 测试"
// 的常见闭环，又能避免模型一次输出过长计划导致执行发散。
public const MAX_PLAN_STEPS: Int64 = 6

public struct AgentConfig {
    public AgentConfig(public let workspaceRoot: String,
                       public let serviceDir: String,
                       public let provider: String,
                       public let model: String,
                       public let maxRounds: Int64,
                       public let prompt: String) {}
}

// PlannedToolCall 表示规划阶段产出的单个 MCP 工具调用，
// 其中保留 reason，便于打印计划和在 replanning 时回溯上下文。
public struct PlannedToolCall {
    public PlannedToolCall(public let tool: String,
                           public let arguments: JsonObject,
                           public let reason: String) {}
}

// AgentPlan 是一轮规划的摘要与步骤集合。
public struct AgentPlan {
    public AgentPlan(public let summary: String,
                     public let steps: Array<PlannedToolCall>) {}
}

// ToolExecution 保存实际执行结果，既用于最终总结，
// 也用于下一轮 replanning 时判断是否需要补充动作。
public struct ToolExecution {
    public ToolExecution(public let tool: String,
                         public let arguments: JsonObject,
                         public let ok: Bool,
                         public let summary: String,
                         public let preview: String) {}
}

// ModelTurn 统一封装一次模型对话的返回
public struct ModelTurn {
    public ModelTurn(public let reply: String,
                     public let sessionId: String,
                     public let success: Bool) {}
}

// AgentPlanningContext 收集规划阶段会用到的外部上下文快照
public struct AgentPlanningContext {
    public AgentPlanningContext(public let userPrompt: String,
                                public let toolsJson: String,
                                public let workspaceSnapshot: String) {}
}
