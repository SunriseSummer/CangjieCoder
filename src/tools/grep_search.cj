package cangjiecoder.tools

import std.collection.*
import std.fs.*
import std.regex.*
import cangjiecoder.common.*

/**
 * `grep_search` 工具：在目录树中按正则搜索匹配行
 *
 * - 按 glob 过滤候选文件（默认 `**` 通配），
 * - 匹配方式为逐行正则，
 * - 输出格式：`<file>:<lineno>: <line>`
 */
public class GrepTool <: Tool {
    public prop name: String {
        get() {
            return "grep_search"
        }
    }

    public prop description: String {
        get() {
            return "在指定目录下按正则表达式搜索文件内容，类似 ripgrep。" + "可通过 file_glob 限定文件范围。"
        }
    }

    public prop parametersSchemaJson: String {
        get() {
            return ##"""
{
  "type": "object",
  "properties": {
    "pattern": {"type": "string", "description": "正则表达式（仓颉 Regex 语法）"},
    "root": {"type": "string", "description": "搜索根目录，默认 \".\"", "default": "."},
    "file_glob": {"type": "string", "description": "限定文件名 glob，默认 \"**/*\""},
    "limit": {"type": "integer", "description": "最多返回的匹配行数，默认 200", "minimum": 1}
  },
  "required": ["pattern"]
}
"""##
        }
    }

    public prop approval: ApprovalLevel {
        get() {
            return Safe
        }
    }

    public func execute(argumentsJson: String): ToolResult {
        let args = parseArgs(argumentsJson)
        let pattern = requireString(args, "pattern") ?? return ToolResult.err("缺少必填参数 pattern")
        var root = getString(args, "root")
        if (root.isEmpty()) {
            root = "."
        }
        var fileGlob = getString(args, "file_glob")
        if (fileGlob.isEmpty()) {
            fileGlob = "**/*"
        }
        let limit = getPositiveInt(args, "limit", default: 200)
        let rootPath = Path(root)
        if (!exists(rootPath)) {
            return ToolResult.err("根目录不存在: ${root}")
        }
        let re = match (tryCompileRegex(pattern)) {
            case Some(r) => r
            case None => return ToolResult.err("无效正则: ${pattern}")
        }
        let results = ArrayList<String>()
        try {
            grepDir(rootPath, root, fileGlob, re, results, limit)
        } catch (e: Exception) {
            return ToolResult.err("搜索失败: ${e.message}")
        }
        let sb = StringBuilder()
        sb.append("// 命中 ${results.size} 行\n")
        for (line in results) {
            sb.append(line)
            sb.append("\n")
        }
        return ToolResult.ok(sb.toString())
    }
}

func grepDir(dir: Path, displayPrefix: String, fileGlob: String, re: Regex, out: ArrayList<String>, limit: Int64): Unit {
    walkDir(dir, displayPrefix) {
        childFs, childDisplay, isDir =>
            if (out.size >= limit) {
                return false
            }
            if (!isDir && globMatch(fileGlob, childDisplay)) {
                grepFile(childFs, childDisplay, re, out, limit)
            }
            return out.size < limit
    }
}

// grep 结果单行截断限制（字节）
let GREP_LINE_TRUNCATE_LIMIT: Int64 = 240

func grepFile(file: Path, display: String, re: Regex, out: ArrayList<String>, limit: Int64): Unit {
    let text = tryReadFileText(file) ?? return
    let lines = text.split("\n")
    for (i in 0..lines.size) {
        if (out.size >= limit) {
            return
        }
        let line = lines[i]
        if (re.find(line).isSome()) {
            out.add("${display}:${i + 1}: ${truncateWithEllipsis(line, GREP_LINE_TRUNCATE_LIMIT)}")
        }
    }
}

/** 安全编译正则表达式，语法非法时返回 None */
func tryCompileRegex(pattern: String): ?Regex {
    try {
        Some(Regex(pattern))
    } catch (_: Exception) {
        None
    }
}
