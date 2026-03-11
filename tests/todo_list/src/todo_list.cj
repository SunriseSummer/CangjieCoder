// 待办事项 CLI 应用
// 演示：enum、struct、ArrayList、模式匹配、字符串处理、格式化输出
package todo_list

import std.collection.*

// 任务优先级枚举
public enum Priority <: ToString & Equatable<Priority> {
    | Low | Medium | High

    public func toString(): String {
        match (this) {
            case Low => "Low"
            case Medium => "Medium"
            case High => "High"
        }
    }

    public operator func ==(other: Priority): Bool {
        match ((this, other)) {
            case (Low, Low) => true
            case (Medium, Medium) => true
            case (High, High) => true
            case _ => false
        }
    }

    public operator func !=(other: Priority): Bool {
        return !(this == other)
    }
}

// 从字符串解析优先级
public func parsePriority(text: String): Priority {
    let lower = text.toAsciiLower().trimAscii()
    match (lower) {
        case "high" | "h" => Priority.High
        case "medium" | "m" => Priority.Medium
        case _ => Priority.Low
    }
}

// 任务状态枚举
public enum TaskStatus <: ToString & Equatable<TaskStatus> {
    | Pending | Done

    public func toString(): String {
        match (this) {
            case Pending => "Pending"
            case Done => "Done"
        }
    }

    public operator func ==(other: TaskStatus): Bool {
        match ((this, other)) {
            case (Pending, Pending) => true
            case (Done, Done) => true
            case _ => false
        }
    }

    public operator func !=(other: TaskStatus): Bool {
        return !(this == other)
    }
}

// 待办事项数据结构
public struct TodoItem {
    public TodoItem(public let id: Int64,
                    public let title: String,
                    public let priority: Priority,
                    public var status: TaskStatus) {}
}

// 待办事项管理器
public class TodoManager {
    let items = ArrayList<TodoItem>()
    var nextId: Int64 = 1

    public init() {}

    // 添加待办事项
    public func add(title: String, priority!: Priority = Priority.Medium): TodoItem {
        let item = TodoItem(nextId, title, priority, TaskStatus.Pending)
        nextId += 1
        items.add(item)
        return item
    }

    // 标记完成
    public func complete(id: Int64): Bool {
        for (index in 0..items.size) {
            if (items[index].id == id) {
                let item = items[index]
                items[index] = TodoItem(item.id, item.title, item.priority, TaskStatus.Done)
                return true
            }
        }
        return false
    }

    // 删除待办事项
    public func remove(id: Int64): Bool {
        for (index in 0..items.size) {
            if (items[index].id == id) {
                items.remove(at: index)
                return true
            }
        }
        return false
    }

    // 获取所有待办事项
    public func listAll(): Array<TodoItem> {
        return items.toArray()
    }

    // 按状态过滤
    public func listByStatus(status: TaskStatus): Array<TodoItem> {
        let filtered = ArrayList<TodoItem>()
        for (item in items) {
            if (item.status == status) {
                filtered.add(item)
            }
        }
        return filtered.toArray()
    }

    // 按优先级过滤
    public func listByPriority(priority: Priority): Array<TodoItem> {
        let filtered = ArrayList<TodoItem>()
        for (item in items) {
            if (item.priority == priority) {
                filtered.add(item)
            }
        }
        return filtered.toArray()
    }

    // 统计
    public func count(): Int64 {
        return items.size
    }

    public func countPending(): Int64 {
        var n: Int64 = 0
        for (item in items) {
            if (item.status == TaskStatus.Pending) {
                n += 1
            }
        }
        return n
    }

    public func countDone(): Int64 {
        var n: Int64 = 0
        for (item in items) {
            if (item.status == TaskStatus.Done) {
                n += 1
            }
        }
        return n
    }

    // 按优先级排序的待办列表（高优先级在前）
    public func listSortedByPriority(): Array<TodoItem> {
        let high = listByPriority(Priority.High)
        let medium = listByPriority(Priority.Medium)
        let low = listByPriority(Priority.Low)
        let result = ArrayList<TodoItem>()
        for (item in high) { result.add(item) }
        for (item in medium) { result.add(item) }
        for (item in low) { result.add(item) }
        return result.toArray()
    }
}

// 格式化显示单个待办事项
public func formatTodoItem(item: TodoItem): String {
    let statusMark = match (item.status) {
        case Pending => "[ ]"
        case Done => "[x]"
    }
    return "${statusMark} #${item.id} [${item.priority}] ${item.title}"
}

// 格式化显示待办列表
public func formatTodoList(items: Array<TodoItem>): String {
    if (items.isEmpty()) {
        return "(empty)"
    }
    let lines = ArrayList<String>()
    for (item in items) {
        lines.add(formatTodoItem(item))
    }
    return String.join(lines.toArray(), delimiter: "\n")
}

main() {
    let manager = TodoManager()

    // 添加几个待办事项
    manager.add("Learn Cangjie basics", priority: Priority.High)
    manager.add("Write JSON parser", priority: Priority.High)
    manager.add("Set up CI pipeline", priority: Priority.Medium)
    manager.add("Update documentation", priority: Priority.Low)
    manager.add("Review pull requests", priority: Priority.Medium)

    println("=== All Tasks ===")
    println(formatTodoList(manager.listAll()))

    // 完成一些任务
    manager.complete(1)
    manager.complete(3)

    println("\n=== Pending Tasks ===")
    println(formatTodoList(manager.listByStatus(TaskStatus.Pending)))

    println("\n=== Completed Tasks ===")
    println(formatTodoList(manager.listByStatus(TaskStatus.Done)))

    println("\n=== High Priority ===")
    println(formatTodoList(manager.listByPriority(Priority.High)))

    println("\n=== Sorted by Priority ===")
    println(formatTodoList(manager.listSortedByPriority()))

    println("\n=== Statistics ===")
    println("Total: ${manager.count()}, Pending: ${manager.countPending()}, Done: ${manager.countDone()}")
}
