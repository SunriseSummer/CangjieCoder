// 应用入口：演示典型仓颉项目结构和组件协作
package testproject

import std.collection.*

main() {
    println("TaskManager v0.1.0")

    let store = TaskStore()
    store.add(Task("设计系统架构", priority: Priority.HIGH))
    store.add(Task("编写单元测试", priority: Priority.MEDIUM))
    store.add(Task("优化性能瓶颈", priority: Priority.HIGH))
    store.add(Task("更新项目文档", priority: Priority.LOW))

    let highPriority = store.search(TaskFilter(minPriority: Priority.HIGH))
    println("高优先级任务: ${highPriority.size}")

    for (task in highPriority) {
        println("  - ${task.title} [${task.status}]")
    }

    store.complete("设计系统架构")
    let stats = store.statistics()
    println("统计: 共 ${stats.total} 个任务, ${stats.completed} 个已完成")
}
