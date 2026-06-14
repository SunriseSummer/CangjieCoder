package cangjiecoder.app

import std.env.*
import cangjiecoder.commands.*
import cangjiecoder.httpx.*

/**
 * 主交互循环（REPL）
 *
 * 行为：
 *  - `/` 开头视为命令，交由 `dispatch` 处理，
 *  - 其余文本根据 ctx.mode 选择：
 *      * Chat   - 经 chat session 发送（流式）
 *      * Agent  - 进入 agent loop（多轮工具调用）
 *  - Ctrl-D（EOF）或 `/exit` 退出
 *
 * 实现细节：当 stdout 是管道（例如被脚本/E2E 驱动）时，glibc 默认
 * 行缓冲会变为块缓冲，导致交互延迟这里在每轮提示符后显式 flush，
 * 让上游始终能看到完整的提示信息和回复
 */

public func runRepl(ctx: Context): Int64 {
    printBanner(ctx)
    getStdOut().flush()
    while (true) {
        println("")
        println("[user-input]")
        print("> ")
        getStdOut().flush()
        let line = match (getStdIn().readln()) {
            case Some(s) => s
            case None =>
                println("")
                println("再见！")
                getStdOut().flush()
                return 0
        }
        let trimmed = line.trimAscii()
        if (trimmed.isEmpty()) {
            continue
        }
        if (trimmed.startsWith("/")) {
            match (dispatch(trimmed, ctx)) {
                case Exit =>
                    getStdOut().flush()
                    return 0
                case Continue => ()
            }
            getStdOut().flush()
            continue
        }
        match (ctx.mode) {
            case Chat => sendChat(ctx, trimmed)
            case Agent => sendAgent(ctx, trimmed)
        }
        getStdOut().flush()
    }
    return 0
}

func sendChat(ctx: Context, message: String): Unit {
    let started = StreamState()
    let onChunk: StreamCallback = {
        chunk: String =>
        if (!started.value) {
            print("${ctx.model.displayName}> ")
            started.value = true
        }
        print(chunk, flush: true)
    }
    try {
        let reply = ctx.session.send(message, Some(onChunk))
        if (started.value) {
            println("")
        } else {
            println("${ctx.model.displayName}> ${reply}")
        }
    } catch (e: Exception) {
        if (started.value) { println("") }
        eprintln("请求失败: ${e.message}")
    }
}

func sendAgent(ctx: Context, message: String): Unit {
    try {
        let reply = ctx.agent.run(message)
        println("")
        println("[final]")
        println("${ctx.model.displayName}> ${reply}")
    } catch (e: Exception) {
        eprintln("agent 请求失败: ${e.message}")
    }
}

class StreamState {
    public var value: Bool = false
}
