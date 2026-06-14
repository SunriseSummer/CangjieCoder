package cangjiecoder.tools

import std.collection.*

/**
 * 工具注册中心
 *
 * 由 `defaultRegistry()` 返回内建工具的默认集合
 * 也可手动 `add` 自定义工具，或 `remove` 危险工具来收紧权限
 */

public class ToolRegistry {
    let order: ArrayList<String>
    let map: HashMap<String, Tool>

    public init() {
        this.order = ArrayList<String>()
        this.map = HashMap<String, Tool>()
    }

    public func add(t: Tool): Unit {
        if (this.map.contains(t.name)) {
            this.map[t.name] = t
            return
        }
        this.order.add(t.name)
        this.map[t.name] = t
    }

    public func remove(name: String): Unit {
        if (!this.map.contains(name)) {
            return
        }
        this.map.remove(name)
        for (i in 0..this.order.size) {
            if (this.order[i] == name) {
                this.order.remove(at: i)
                break
            }
        }
    }

    public func get(name: String): ?Tool {
        return this.map.get(name)
    }

    public func names(): ArrayList<String> {
        return this.order
    }

    public func all(): ArrayList<Tool> {
        let out = ArrayList<Tool>()
        for (name in this.order) {
            if (let Some(tool) <- this.map.get(name)) {
                out.add(tool)
            }
        }
        return out
    }
}
