package cangjiecoder.agent

import cangjiecoder.common.*
import cangjiecoder.tools.*

/**
 * 工具调用前的审批策略
 *
 *  - Auto       自动放行所有工具
 *  - Default    Safe 工具自动放行，Sensitive 工具询问用户（y/n/a）
 *  - ReadOnly   Sensitive 工具一律拒绝
 *
 * 用户在交互提示符中输入 `a` 可临时升级为 Auto
 */

public enum ApprovalPolicy {
    | Auto
    | Default_
    | ReadOnly
}

public func approvalPolicyName(p: ApprovalPolicy): String {
    return match (p) {
        case Auto => "auto"
        case Default_ => "default"
        case ReadOnly => "readonly"
    }
}

public func parseApprovalPolicy(s: String): ?ApprovalPolicy {
    return match (s.toAsciiLower()) {
        case "auto" | "yolo" => Some(Auto)
        case "default" | "normal" => Some(Default_)
        case "readonly" | "ro" | "read" => Some(ReadOnly)
        case _ => None
    }
}

public class Approver {
    public var policy: ApprovalPolicy

    public init(policy: ApprovalPolicy) {
        this.policy = policy
    }

    /** 返回 (允许, 是否切换至 Auto)允许=false 时调用方应跳过该工具并写回错误 */
    public func confirm(toolName: String, argumentsJson: String, level: ApprovalLevel): (Bool, Bool) {
        match (level) {
            case Safe => return (true, false)
            case Sensitive => ()
        }
        match (this.policy) {
            case Auto => return (true, false)
            case ReadOnly =>
                eprintln("")
                eprintln("[审批]")
                eprintln("当前为 readonly 模式，已拒绝敏感工具 ${toolName}")
                return (false, false)
            case Default_ => return promptUser(toolName, argumentsJson)
        }
    }
}

// 审批提示的参数截断限制（字节）
let APPROVAL_TRUNCATE_LIMIT: Int64 = 600

func promptUser(toolName: String, argumentsJson: String): (Bool, Bool) {
    println("")
    println("[审批]")
    println("敏感工具: ${toolName}")
    println("  ${truncateWithEllipsis(argumentsJson, APPROVAL_TRUNCATE_LIMIT)}")
    print("  允许？[y]es / [n]o / [a]uto > ")
    let line = readln().trimAscii().toAsciiLower()
    match (line) {
        case "a" | "all" | "auto" => return (true, true)
        case "y" | "yes" | "" => return (true, false)
        case _ =>
            println("  已拒绝。")
            return (false, false)
    }
}
