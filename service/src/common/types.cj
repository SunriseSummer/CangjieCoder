// 共享类型定义：根包和子包通用的应用配置和常量
package cangjiecoder.common

public const APP_VERSION: String = "0.4.0"

public struct AppConfig {
    public AppConfig(public let workspaceRoot: String,
                     public let serviceRoot: String,
                     public let hasExplicitRepo: Bool) {}
}
