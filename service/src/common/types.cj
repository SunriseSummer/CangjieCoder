// 共享类型定义：根包和子包通用的应用配置和常量
package cangjiecoder.common

import stdx.encoding.json.*

public const APP_VERSION: String = "0.4.0"

public struct AppConfig {
    public AppConfig(public let workspaceRoot: String,
                     public let serviceRoot: String,
                     public let hasExplicitRepo: Bool) {}
}

// MCP 工具上下文 —— 每次 tools/call 携带的运行时环境
public struct McpToolContext {
    public McpToolContext(public let workspaceRoot: String,
                          public let serviceRoot: String) {}
}

// MCP 工具处理函数类型
public type McpToolHandler = (McpToolContext, JsonObject) -> String
