package cangjiecoder.commands

import cangjiecoder.tools.*

/**
 * 文件改动相关命令：/diff 与 /undo
 *
 * 设计参考 aider：
 *  - `/diff`：列出本会话中所有被 edit_file / write_file 改动过的文件，
 *    以「日志起点字节数 → 当前字节数」的形式呈现摘要，方便用户审查
 *    模型自动编辑的最终结果
 *  - `/undo`：弹出最近一次 FileSnapshot 并把对应文件回滚到改动前的状态
 *    支持多次连续 undo（栈式）
 */

public func handleDiff(_: String, ctx: Context): CommandResult {
    let entries = ctx.journal.summary()
    if (entries.size == 0) {
        println("尚未发生任何文件改动。")
        return Continue
    }
    println("本会话累计文件改动（共 ${entries.size} 个文件 / ${ctx.journal.size()} 次操作）：")
    for (i in 0..entries.size) {
        let (path, beforeBytes, nowBytes, existedBefore, existsNow) = entries[i]
        let lhs = if (existedBefore) { "${beforeBytes}B" } else { "(新增)" }
        let rhs = if (existsNow) { "${nowBytes}B" } else { "(已删除)" }
        let delta = if (existedBefore && existsNow) {
            let diff = nowBytes - beforeBytes
            if (diff >= 0) { "  Δ +${diff}B" } else { "  Δ ${diff}B" }
        } else { "" }
        println("  ${i + 1}. ${path}")
        println("     ${lhs}  →  ${rhs}${delta}")
    }
    println("提示：使用 /undo 可逐步回滚最近的改动。")
    return Continue
}

public func handleUndo(_: String, ctx: Context): CommandResult {
    match (ctx.journal.popLast()) {
        case None =>
            println("没有可回滚的文件改动。")
            return Continue
        case Some(s) =>
            try {
                let msg = ctx.journal.revert(s)
                println("${msg}（由 ${s.tool} 触发）")
            } catch (e: Exception) {
                eprintln("回滚失败: ${e.message}")
            }
            return Continue
    }
}
