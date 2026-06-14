package cangjiecoder.commands

/**
 * 斜杠命令分发器
 *
 * 输入形如 `/cmd arg1 arg2 ...` 的字符串，根据命令名路由到对应处理器
 * 未知命令打印提示并继续
 */

public func dispatch(line: String, ctx: Context): CommandResult {
    let (cmd, arg) = splitCommand(line)
    match (cmd) {
        case "/help" | "/h" | "/?" => return handleHelp(arg, ctx)
        case "/exit" | "/quit" | "/q" => return handleExit(arg, ctx)
        case "/clear" => return handleClear(arg, ctx)
        case "/system" => return handleSystem(arg, ctx)
        case "/skills" | "/skill" => return handleSkills(arg, ctx)

        case "/status" => return handleStatus(arg, ctx)
        case "/connect" => return handleConnect(arg, ctx)
        case "/model" => return handleModel(arg, ctx)
        case "/mode" => return handleMode(arg, ctx)
        case "/approve" | "/approval" => return handleApprove(arg, ctx)
        case "/tools" | "/tool" => return handleTools(arg, ctx)
        case "/todo" | "/todos" => return handleTodo(arg, ctx)
        case "/diff" => return handleDiff(arg, ctx)
        case "/undo" => return handleUndo(arg, ctx)
        case "/compact" => return handleCompact(arg, ctx)
        case _ =>
            eprintln("未知命令: ${cmd}，输入 /help 查看可用命令。")
            return Continue
    }
}

func splitCommand(line: String): (String, String) {
    let trimmed = line.trimAscii()
    let idx = trimmed.indexOf(" ")
    match (idx) {
        case Some(i) => return (trimmed[..i].toAsciiLower(), trimmed[i + 1..].trimAscii())
        case None => return (trimmed.toAsciiLower(), "")
    }
}
