package cangjiecoder.tools

import std.collection.*
import std.env.*
import std.process.*
import std.sync.*
import cangjiecoder.common.*

/**
 * `run_bash` 工具：在当前工作目录下执行 shell 命令
 *
 * 安全：
 *  - 通过系统默认 shell 执行（类 Unix 平台用 `/bin/sh -c`，
 *    Windows 平台用 `cmd.exe /c`），避免外部依赖 bash，
 *  - 标记为 Sensitive，需要审批，
 *  - 超时由 timeout_seconds 控制（默认 60s，最大 600s），
 *    超时后强制终止子进程并返回错误
 */

/**
 * 返回当前平台的 shell 可执行文件与参数前缀
 * Windows 使用 cmd.exe，其余平台使用 /bin/sh
 */
@When[os == "Windows"]
func shellInvocation(command: String): (String, Array<String>) {
    return ("cmd.exe", ["/c", command])
}

@When[os != "Windows"]
func shellInvocation(command: String): (String, Array<String>) {
    return ("/bin/sh", ["-c", command])
}

/**
 * 构造子进程环境变量
 *
 * Windows 平台控制台默认使用 GBK(cp936) 代码页，Python 等程序在向
 * 非 TTY 管道输出时会按区域设置编码（GBK）写出，一旦脚本打印诸如
 * `✓` 等 GBK 无法表示的 Unicode 字符，子进程自身就会抛出
 * UnicodeEncodeError 而崩溃（与本工具的解码无关）
 *
 * 这里在继承当前进程全部环境变量的基础上，强制 Python 子进程以 UTF-8
 * 进行标准流 I/O，从根源上消除该编码不兼容问题，本工具的
 * `decodeTextLenient` 会优先按 UTF-8 解码，二者配合即可正确显示
 */
@When[os == "Windows"]
func buildChildEnvironment(): ?Map<String, String> {
    let env = HashMap<String, String>()
    for ((k, v) in getVariables()) {
        env[k] = v
    }
    env["PYTHONIOENCODING"] = "utf-8"
    env["PYTHONUTF8"] = "1"
    return env
}

@When[os != "Windows"]
func buildChildEnvironment(): ?Map<String, String> {
    return None
}

// 命令执行超时控制
let DEFAULT_COMMAND_TIMEOUT: Int64 = 60
let MAX_COMMAND_TIMEOUT: Int64 = 600

// 输出截断阈值（字节）
let MAX_OUTPUT_BYTES: Int64 = 4000

public class RunBashTool <: Tool {
    public prop name: String {
        get() {
            return "run_bash"
        }
    }

    public prop description: String {
        get() {
            return "在当前工作目录下执行 shell 命令（类 Unix 平台通过 /bin/sh -c，" +
                "Windows 平台通过 cmd.exe /c）。" + "适合执行 build / test / lint / git 等操作。" +
                "请避免任何具有破坏性的命令；如需删除文件，请提示用户确认。"
        }
    }

    public prop parametersSchemaJson: String {
        get() {
            return ##"""
{
  "type": "object",
  "properties": {
    "command": {"type": "string", "description": "要执行的 shell 命令"},
    "timeout_seconds": {"type": "integer", "description": "执行超时秒数，默认 60，最大 600", "minimum": 1, "maximum": 600}
  },
  "required": ["command"]
}
"""##
        }
    }

    public prop approval: ApprovalLevel {
        get() {
            return Sensitive
        }
    }

    public func execute(argumentsJson: String): ToolResult {
        let args = parseArgs(argumentsJson)
        let command = getString(args, "command")
        if (command.trimAscii().isEmpty()) {
            return ToolResult.err("命令为空")
        }
        var timeout = getInt(args, "timeout_seconds", default: DEFAULT_COMMAND_TIMEOUT)
        if (timeout <= 0) {
            timeout = DEFAULT_COMMAND_TIMEOUT
        }
        if (timeout > MAX_COMMAND_TIMEOUT) {
            timeout = MAX_COMMAND_TIMEOUT
        }
        try {
            let (shell, shellArgs) = shellInvocation(command)
            let (code, stdoutBytes, stderrBytes, timedOut) = executeWithTimeout(shell, shellArgs, timeout)
            let stdoutText = decodeTextLenient(stdoutBytes) ?? "<二进制输出, ${stdoutBytes.size} 字节>"
            let stderrText = decodeTextLenient(stderrBytes) ?? "<二进制输出, ${stderrBytes.size} 字节>"
            let sb = StringBuilder()
            if (timedOut) {
                sb.append("exit_code: -1 (超时，已终止进程)\n")
            } else {
                sb.append("exit_code: ${code}\n")
            }
            if (!stdoutText.isEmpty()) {
                sb.append("--- stdout ---\n")
                sb.append(truncateHeadTail(stdoutText, MAX_OUTPUT_BYTES))
                sb.append("\n")
            }
            if (!stderrText.isEmpty()) {
                sb.append("--- stderr ---\n")
                sb.append(truncateHeadTail(stderrText, MAX_OUTPUT_BYTES))
                sb.append("\n")
            }
            if (timedOut) {
                sb.append("命令执行超时（${timeout}s），已强制终止。\n")
            }
            return ToolResult(sb.toString(), isError: code != 0 || timedOut)
        } catch (e: Exception) {
            return ToolResult.err("命令执行失败: ${e.message}")
        }
    }
}

/**
 * 带超时的命令执行：使用 launch + waitOutput 并通过 Timer 在超时后强制终止
 * 返回 (exitCode, stdout, stderr, timedOut)
 */
func executeWithTimeout(cmd: String, args: Array<String>, timeoutSec: Int64): (Int64, Array<Byte>, Array<Byte>, Bool) {
    let proc = launch(cmd, args, environment: buildChildEnvironment(), stdOut: ProcessRedirect.Pipe,
        stdErr: ProcessRedirect.Pipe)
    let timedOut = AtomicBool(false)
    let timer = Timer.once(Duration.second * timeoutSec) {
        timedOut.store(true)
        terminateProcessTree(proc)
    }
    try {
        let (code, stdoutBytes, stderrBytes) = proc.waitOutput()
        timer.cancel()
        return (code, stdoutBytes, stderrBytes, timedOut.load())
    } catch (e: Exception) {
        timer.cancel()
        if (timedOut.load()) {
            return (-1, Array<Byte>(), Array<Byte>(), true)
        }
        throw e
    }
}

@When[os == "Windows"]
func terminateProcessTree(proc: SubProcess): Unit {
    try {
        let killer = launch("taskkill.exe", ["/PID", proc.pid.toString(), "/T", "/F"], stdOut: ProcessRedirect.Discard,
            stdErr: ProcessRedirect.Discard)
        let _ = killer.wait()
    } catch (_: Exception) {
        try {
            proc.terminate(force: true)
        } catch (_: Exception) {
            ()
        }
    }
}

@When[os != "Windows"]
func terminateProcessTree(proc: SubProcess): Unit {
    try {
        proc.terminate(force: true)
    } catch (_: Exception) {
        ()
    }
}
