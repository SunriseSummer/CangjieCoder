// 核心数据模型：任务、优先级、状态等领域类型
package testproject

import std.collection.*

// 任务优先级枚举
public enum Priority {
    | LOW | MEDIUM | HIGH | CRITICAL

    public func label(): String {
        match (this) {
            case LOW => "低"
            case MEDIUM => "中"
            case HIGH => "高"
            case CRITICAL => "紧急"
        }
    }

    public operator func >=(rhs: Priority): Bool {
        return this.ordinal() >= rhs.ordinal()
    }

    func ordinal(): Int64 {
        match (this) {
            case LOW => 0
            case MEDIUM => 1
            case HIGH => 2
            case CRITICAL => 3
        }
    }
}

// 任务状态
public enum Status {
    | PENDING | IN_PROGRESS | COMPLETED | CANCELLED

    public func isTerminal(): Bool {
        match (this) {
            case COMPLETED | CANCELLED => true
            case _ => false
        }
    }

    public func toString(): String {
        match (this) {
            case PENDING => "待处理"
            case IN_PROGRESS => "进行中"
            case COMPLETED => "已完成"
            case CANCELLED => "已取消"
        }
    }
}

// 任务筛选条件
public struct TaskFilter {
    public TaskFilter(
        public let minPriority!: Priority = Priority.LOW,
        public let status!: ?Status = None,
        public let keyword!: String = ""
    ) {}
}

// 统计结果
public struct TaskStats {
    public TaskStats(
        public let total: Int64,
        public let completed: Int64,
        public let pending: Int64,
        public let highPriority: Int64
    ) {}
}

// 任务实体
public class Task {
    public let title: String
    public var priority: Priority
    public var status: Status = Status.PENDING
    public var tags: ArrayList<String> = ArrayList<String>()

    public init(title: String, priority!: Priority = Priority.MEDIUM) {
        this.title = title
        this.priority = priority
    }

    public func complete(): Unit {
        status = Status.COMPLETED
    }

    public func cancel(): Unit {
        status = Status.CANCELLED
    }

    public func addTag(tag: String): Unit {
        if (!tags.contains(tag)) {
            tags.add(tag)
        }
    }

    public func matchesFilter(filter: TaskFilter): Bool {
        if (!(priority >= filter.minPriority)) {
            return false
        }
        if (let Some(s) <- filter.status) {
            if (status.toString() != s.toString()) {
                return false
            }
        }
        if (!filter.keyword.isEmpty()) {
            return title.contains(filter.keyword)
        }
        return true
    }
}
