// 任务存储与查询：管理任务集合，提供搜索和统计功能
package testproject

import std.collection.*

// 任务存储
public class TaskStore {
    let tasks = ArrayList<Task>()

    // 添加任务
    public func add(task: Task): Unit {
        tasks.add(task)
    }

    // 按条件搜索任务
    public func search(filter: TaskFilter): ArrayList<Task> {
        let results = ArrayList<Task>()
        for (task in tasks) {
            if (task.matchesFilter(filter)) {
                results.add(task)
            }
        }
        return results
    }

    // 按标题完成任务
    public func complete(title: String): Bool {
        for (task in tasks) {
            if (task.title == title && !task.status.isTerminal()) {
                task.complete()
                return true
            }
        }
        return false
    }

    // 按标题取消任务
    public func cancel(title: String): Bool {
        for (task in tasks) {
            if (task.title == title && !task.status.isTerminal()) {
                task.cancel()
                return true
            }
        }
        return false
    }

    // 获取统计信息
    public func statistics(): TaskStats {
        var completed: Int64 = 0
        var pending: Int64 = 0
        var highPriority: Int64 = 0
        for (task in tasks) {
            match (task.status) {
                case COMPLETED => completed += 1
                case PENDING | IN_PROGRESS => pending += 1
                case _ => ()
            }
            if (task.priority >= Priority.HIGH) {
                highPriority += 1
            }
        }
        return TaskStats(tasks.size, completed, pending, highPriority)
    }

    // 任务总数
    public prop count: Int64 {
        get() { tasks.size }
    }
}

// 文本格式化工具
public func formatTaskList(tasks: ArrayList<Task>): String {
    let lines = ArrayList<String>()
    for (task in tasks) {
        let tagStr = if (task.tags.isEmpty()) {
            ""
        } else {
            let tagParts = ArrayList<String>()
            for (tag in task.tags) {
                tagParts.add(tag)
            }
            " [${String.join(tagParts.toArray(), delimiter: ", ")}]"
        }
        lines.add("- ${task.title} (${task.priority.label()}) ${task.status.toString()}${tagStr}")
    }
    return String.join(lines.toArray(), delimiter: "\n")
}

// 字符串工具函数
public func truncateText(text: String, maxLen!: Int64 = 80): String {
    if (text.size <= maxLen) {
        return text
    }
    return "${text[0..maxLen - 3]}..."
}

public func countLines(text: String): Int64 {
    if (text.isEmpty()) {
        return 0
    }
    var count: Int64 = 1
    for (b in text) {
        if (b == 10u8) {  // '\n'
            count += 1
        }
    }
    return count
}
