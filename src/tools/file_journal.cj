package cangjiecoder.tools

import std.collection.*
import std.fs.*

/**
 * 文件变更日志（File Change Journal）
 *
 * 设计参考 aider / Cursor 的「change tracking + undo」机制：
 *  - 在 `edit_file` / `write_file` 真正落盘前，先把文件「改动前的状态」
 *    （绝对路径 + 原始字节内容 + 是否原本存在）压栈，
 *  - `/diff` 命令读取栈中所有 entry，逐文件对比当前磁盘内容与栈底的初始
 *    版本，给出统一变更摘要，
 *  - `/undo` 命令弹出最近一次 entry，把对应文件回退到该 entry 记录的状态：
 *      * 若 entry.existedBefore == false：删除当前文件，恢复「不存在」，
 *      * 否则：把 entry.contentBefore 写回磁盘
 *
 * 线程安全：当前 REPL 单线程使用，不加锁
 *
 * 该结构与 ToolRegistry 一起持有，工具构造函数接收 journal 作为依赖
 */

public class FileSnapshot {
    public let path: String
    public let existedBefore: Bool
    public let contentBefore: Array<Byte>
    public let tool: String

    public init(path: String, existedBefore: Bool, contentBefore: Array<Byte>, tool: String) {
        this.path = path
        this.existedBefore = existedBefore
        this.contentBefore = contentBefore
        this.tool = tool
    }
}

public class FileJournal {
    let stack: ArrayList<FileSnapshot>

    public init() {
        this.stack = ArrayList<FileSnapshot>()
    }

    /** 在写入前记录一次快照tool 为触发方工具名（用于审计 / 展示） */
    public func record(path: String, tool: String): Unit {
        let filePath = Path(path)
        let existed = exists(filePath)
        let content: Array<Byte> = if (existed) {
            match (tryReadBytes(filePath)) {
                case Some(bytes) => bytes
                case None =>
                    // 文件存在但不可读时，记录 existedBefore=true 但内容为空，
                    // 并输出警告/undo 回滚时会将文件恢复为空（可能有数据丢失风险），
                    // 但至少不会错误地将其标记为"新建文件"而在 undo 时删除
                    eprintln("[journal] 警告：${path} 存在但无法读取，快照内容为空")
                    Array<Byte>()
            }
        } else {
            Array<Byte>()
        }
        this.stack.add(FileSnapshot(path, existed, content, tool))
    }

    public func size(): Int64 {
        return this.stack.size
    }

    public func entries(): ArrayList<FileSnapshot> {
        return this.stack
    }

    /** 弹出最后一次快照（用于 /undo），返回 None 表示无可回滚记录 */
    public func popLast(): ?FileSnapshot {
        let count = this.stack.size
        if (count == 0) {
            return None
        }
        let last = this.stack[count - 1]
        this.stack.remove(at: count - 1)
        return Some(last)
    }

    public func clear(): Unit {
        this.stack.clear()
    }

    /**
     * 对单个 snapshot 做回滚返回回滚后的人类可读说明
     * 失败时抛异常
     */
    public func revert(s: FileSnapshot): String {
        let filePath = Path(s.path)
        if (!s.existedBefore) {
            if (exists(filePath)) {
                remove(filePath)
            }
            return "已删除 ${s.path}（恢复为「不存在」状态）"
        }
        // 父目录可能也已被外部清掉，恢复一下
        let parent = filePath.parent
        if (!parent.toString().isEmpty() && !exists(parent)) {
            Directory.create(parent, recursive: true)
        }
        File.writeTo(filePath, s.contentBefore)
        return "已恢复 ${s.path}（${s.contentBefore.size} 字节）"
    }

    /**
     * 返回当前所有受影响文件、按首次出现顺序去重的列表，以及每个文件
     * 「日志起点」的原始字节数和当前字节数`/diff` 命令用它生成摘要
     */
    public func summary(): ArrayList<(String, Int64, Int64, Bool, Bool)> {
        // 元组：(path, beforeBytes, nowBytes, existedBefore, existsNow)
        let seen = HashMap<String, Int64>()
        let out = ArrayList<(String, Int64, Int64, Bool, Bool)>()
        for (snapshot in this.stack) {
            if (seen.contains(snapshot.path)) {
                continue
            }
            seen[snapshot.path] = 1
            let nowExists = exists(Path(snapshot.path))
            let nowSize: Int64 = if (nowExists) {
                match (tryReadBytes(Path(snapshot.path))) {
                    case Some(bytes) => Int64(bytes.size)
                    case None => -1
                }
            } else { 0 }
            out.add((snapshot.path, Int64(snapshot.contentBefore.size), nowSize, snapshot.existedBefore, nowExists))
        }
        return out
    }
}
