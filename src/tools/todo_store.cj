package cangjiecoder.tools

import std.collection.*

/**
 * 全局 TODO 状态：被 `todo_write` 与 `todo_read` 工具共享
 *
 * 设计参考 Anthropic Claude Code 的 TodoWrite 工具：
 *  - 由 agent 自行维护任务清单，便于在多步骤工作中保持专注，
 *  - 状态有 pending / in_progress / completed 三种，
 *  - 同一时刻最多一个 in_progress 项
 */

public class TodoItem {
    public var content: String
    public var status: String   // pending | in_progress | completed
    public var activeForm: String

    public init(content: String, status: String, activeForm: String) {
        this.content = content
        this.status = status
        this.activeForm = activeForm
    }
}

public class TodoStore {
    public let items: ArrayList<TodoItem>

    public init() {
        this.items = ArrayList<TodoItem>()
    }

    public func replaceAll(newItems: ArrayList<TodoItem>): Unit {
        this.items.clear()
        for (it in newItems) {
            this.items.add(it)
        }
    }

    public func render(): String {
        if (this.items.size == 0) {
            return "<尚无 TODO 项>"
        }
        let sb = StringBuilder()
        for (i in 0..this.items.size) {
            let it = this.items[i]
            let mark = match (it.status) {
                case "completed" => "[x]"
                case "in_progress" => "[~]"
                case _ => "[ ]"
            }
            sb.append("${i + 1}. ${mark} ${it.content}\n")
        }
        return sb.toString()
    }
}
