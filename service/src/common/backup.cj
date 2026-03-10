// 文件备份与事务回滚：在修改文件前保存原始内容，支持一键恢复
package cangjiecoder.common

import std.collection.*
import std.fs.*

// FileBackupStore 在修改文件前保存原始内容，支持事务回滚。
// 当 build/test 验证失败时，可以将被破坏的文件恢复到修改前的状态。
public class FileBackupStore {
    let backups = HashMap<String, String>()

    // 在修改文件前备份其当前内容。同一个文件只保存首次备份，
    // 确保回滚时恢复到事务开始前的初始状态。
    public func backup(path: String): Unit {
        if (backups.contains(path)) {
            return
        }
        if (exists(path)) {
            backups[path] = readTextFile(path)
        }
    }

    // 将所有已备份文件恢复到修改前的状态
    public func rollbackAll(): Array<String> {
        let restored = ArrayList<String>()
        for ((path, content) in backups) {
            try {
                writeTextFile(path, content)
                restored.add(path)
            } catch (e: Exception) {
                // 恢复失败时静默跳过，避免级联失败
            }
        }
        backups.clear()
        return restored.toArray()
    }

    // 清除所有备份（事务提交成功后调用）
    public func clear(): Unit {
        backups.clear()
    }

    public prop fileCount: Int64 {
        get() {
            return backups.size
        }
    }

    public func hasBackups(): Bool {
        return !backups.isEmpty()
    }

    public func backedUpPaths(): Array<String> {
        let paths = ArrayList<String>()
        for ((path, _) in backups) {
            paths.add(path)
        }
        return paths.toArray()
    }
}

// 全局备份存储实例，被 MCP 工具处理函数共享
public var globalBackupStore = FileBackupStore()
