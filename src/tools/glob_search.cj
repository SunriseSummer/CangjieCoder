package cangjiecoder.tools

import std.collection.*
import std.fs.*

/**
 * `glob_search` 工具：按文件名通配（**, *, ?）查找文件
 *
 * 自实现简单 glob → 正则的转换，避免引入额外依赖
 * 排除噪声目录（见 list_dir.isNoiseEntry）
 */
public class GlobTool <: Tool {
    public prop name: String {
        get() {
            return "glob_search"
        }
    }

    public prop description: String {
        get() {
            return "在项目目录下按 glob 模式查找文件路径（如 \"**/*.cj\"）。"
        }
    }

    public prop parametersSchemaJson: String {
        get() {
            return ##"""
{
  "type": "object",
  "properties": {
    "pattern": {"type": "string", "description": "Glob 模式，例如 \"**/*.cj\" 或 \"src/**/*.md\""},
    "root": {"type": "string", "description": "搜索根目录，默认 \".\"", "default": "."},
    "limit": {"type": "integer", "description": "最多返回结果数，默认 200", "minimum": 1}
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
        let limit = getPositiveInt(args, "limit", default: 200)
        let rootPath = Path(root)
        if (!exists(rootPath)) {
            return ToolResult.err("根目录不存在: ${root}")
        }
        let matches = ArrayList<String>()
        try {
            walkAndMatch(rootPath, root, pattern, matches, limit)
        } catch (e: Exception) {
            return ToolResult.err("查找失败: ${e.message}")
        }
        let sb = StringBuilder()
        sb.append("// 匹配 ${matches.size} 个文件\n")
        for (matchPath in matches) {
            sb.append(matchPath)
            sb.append("\n")
        }
        return ToolResult.ok(sb.toString())
    }
}

func walkAndMatch(dir: Path, displayPrefix: String, pattern: String, out: ArrayList<String>, limit: Int64): Unit {
    walkDir(dir, displayPrefix) {
        _, childDisplay, isDir =>
            if (out.size >= limit) {
                return false
            }
            if (!isDir && globMatch(pattern, childDisplay)) {
                out.add(childDisplay)
            }
            return out.size < limit
    }
}
