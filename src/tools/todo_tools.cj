package cangjiecoder.tools

import std.collection.*
import stdx.encoding.json.*

/**
 * TODO 任务清单工具：`todo_write` 与 `todo_read`
 *
 * `todo_write` 整体替换 TODO 列表（agent 在每次更新计划时调用）
 * `todo_read` 返回当前列表的快照（一般用于自检 / 用户查询）
 */

public class TodoWriteTool <: Tool {
    let store: TodoStore

    public init(store: TodoStore) {
        this.store = store
    }

    public prop name: String { get() { return "todo_write" } }

    public prop description: String {
        get() {
            return "整体覆盖当前任务清单（不增量更新）。" +
                   "建议在开始多步骤工作前列出计划，并在每个步骤完成时更新对应项状态。" +
                   "status 取值：pending | in_progress | completed；同一时刻最多一个 in_progress。"
        }
    }

    public prop parametersSchemaJson: String {
        get() {
            return ##"""
{
  "type": "object",
  "properties": {
    "todos": {
      "type": "array",
      "description": "完整任务列表",
      "items": {
        "type": "object",
        "properties": {
          "content": {"type": "string", "description": "祈使句形式的任务描述，如 \"实现 read_file 工具\""},
          "status": {"type": "string", "enum": ["pending", "in_progress", "completed"]},
          "activeForm": {"type": "string", "description": "进行中的描述，如 \"正在实现 read_file 工具\""}
        },
        "required": ["content", "status", "activeForm"]
      }
    }
  },
  "required": ["todos"]
}
"""##
        }
    }

    public prop approval: ApprovalLevel { get() { return Safe } }

    public func execute(argumentsJson: String): ToolResult {
        let args = parseArgs(argumentsJson)
        let arr = match (args.get("todos")) {
            case Some(v) =>
                match (v.kind()) {
                    case JsArray => v.asArray()
                    case _ => return ToolResult.err("todos 必须是数组")
                }
            case None => return ToolResult.err("缺少必填参数 todos")
        }
        let items = ArrayList<TodoItem>()
        var inProgress = 0
        for (i in 0..arr.size()) {
            let item = arr[i]
            match (item.kind()) {
                case JsObject => ()
                case _ => return ToolResult.err("todos[${i}] 必须是对象")
            }
            let obj = item.asObject()
            let content = getString(obj, "content")
            let status = getString(obj, "status", default: "pending")
            let activeForm = getString(obj, "activeForm", default: content)
            if (content.isEmpty()) {
                return ToolResult.err("todos[${i}].content 不能为空")
            }
            if (status != "pending" && status != "in_progress" && status != "completed") {
                return ToolResult.err("todos[${i}].status 无效: ${status}（仅支持 pending/in_progress/completed）")
            }
            if (status == "in_progress") {
                inProgress++
            }
            items.add(TodoItem(content, status, activeForm))
        }
        if (inProgress > 1) {
            return ToolResult.err("同一时刻最多一个 in_progress（当前 ${inProgress} 个）")
        }
        this.store.replaceAll(items)
        return ToolResult.ok("已更新任务清单（${items.size} 项）：\n${this.store.render()}")
    }
}

public class TodoReadTool <: Tool {
    let store: TodoStore

    public init(store: TodoStore) {
        this.store = store
    }

    public prop name: String { get() { return "todo_read" } }

    public prop description: String {
        get() { return "读取当前任务清单的快照（无参数）。" }
    }

    public prop parametersSchemaJson: String {
        get() { return ##"""{"type": "object", "properties": {}}"""## }
    }

    public prop approval: ApprovalLevel { get() { return Safe } }

    public func execute(_: String): ToolResult {
        return ToolResult.ok(this.store.render())
    }
}
