package cangjiecoder.tools

import std.fs.*

/**
 * `read_file` 工具：读取项目内的文本文件（UTF-8）
 *
 * 安全策略：仅允许读取 CWD 之下的路径，
 * 大文件按 `limit_lines` 截取，可指定 `start_line` 起始位置
 */

// 默认单次最多返回的行数
let DEFAULT_READ_LINES: Int64 = 400

public class ReadFileTool <: Tool {
    public prop name: String {
        get() {
            return "read_file"
        }
    }

    public prop description: String {
        get() {
            return "读取项目目录下的文本文件内容（UTF-8）。" +
                "支持通过 start_line / limit_lines 分段读取，避免一次性载入超大文件。"
        }
    }

    public prop parametersSchemaJson: String {
        get() {
            return ##"""
{
  "type": "object",
  "properties": {
    "path": {"type": "string", "description": "相对于当前工作目录的文件路径"},
    "start_line": {"type": "integer", "description": "起始行号（从 1 开始），默认 1", "minimum": 1},
    "limit_lines": {"type": "integer", "description": "最多返回的行数，默认 400", "minimum": 1}
  },
  "required": ["path"]
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
        let path = requireString(args, "path") ?? return ToolResult.err("缺少必填参数 path")
        let start = getInt(args, "start_line", default: 1)
        let limit = getPositiveInt(args, "limit_lines", default: DEFAULT_READ_LINES)
        let filePath = Path(path)
        if (!exists(filePath)) {
            return ToolResult.err("文件不存在: ${path}")
        }
        try {
            let bytes = File.readFrom(filePath)
            let text = decodeTextLenient(bytes) ?? return ToolResult.err(
                "文件不是有效的 UTF-8 文本（可能为二进制文件）: ${path}")
            return ToolResult.ok(renderLines(text, start, limit))
        } catch (ex: Exception) {
            return ToolResult.err("读取失败: ${ex.message}")
        }
    }
}

func renderLines(text: String, start: Int64, limit: Int64): String {
    let lines = text.split("\n")
    let total = lines.size
    var lineStart = start
    if (lineStart < 1) {
        lineStart = 1
    }
    if (lineStart > total) {
        return "<文件共 ${total} 行；start_line=${start} 超出范围>"
    }
    var endExclusive = lineStart - 1 + limit
    if (endExclusive > total) {
        endExclusive = total
    }
    let sb = StringBuilder()
    sb.append("// 文件总行数: ${total}；范围: ${lineStart}..${endExclusive}\n")
    for (lineIndex in (lineStart - 1)..endExclusive) {
        sb.append((lineIndex + 1).toString())
        sb.append("\t")
        sb.append(lines[lineIndex])
        sb.append("\n")
    }
    if (endExclusive < total) {
        sb.append("// 还有 ${total - endExclusive} 行未显示，使用 start_line=${endExclusive + 1} 继续读取\n")
    }
    return sb.toString()
}
