package cangjiecoder.tools

import std.fs.*

/**
 * `edit_file` 工具：通过精确字符串替换在已有文件中进行外科手术式编辑
 *
 * 模式参考 Anthropic Claude Code / aider 的 `str_replace`：
 *  - `old_str` 必须在文件中**唯一**出现（避免误改），
 *  - 多处替换请多次调用本工具
 *
 * 属于敏感操作，需要审批
 */
public class EditFileTool <: Tool {
    let journal: ?FileJournal

    public init() {
        this.journal = None
    }

    public init(journal: FileJournal) {
        this.journal = Some(journal)
    }

    public prop name: String {
        get() {
            return "edit_file"
        }
    }

    public prop description: String {
        get() {
            return "对已有文件做精确字符串替换。old_str 必须在文件中唯一匹配；" +
                "若有多处匹配将拒绝执行，请增加上下文以唯一定位。"
        }
    }

    public prop parametersSchemaJson: String {
        get() {
            return ##"""
{
  "type": "object",
  "properties": {
    "path": {"type": "string", "description": "目标文件路径（相对于当前工作目录）"},
    "old_str": {"type": "string", "description": "待替换的旧字符串，必须在文件中唯一出现"},
    "new_str": {"type": "string", "description": "替换为的新字符串"}
  },
  "required": ["path", "old_str", "new_str"]
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
        let path = requireString(args, "path") ?? return ToolResult.err("缺少必填参数 path 或 old_str")
        let oldStr = requireString(args, "old_str") ?? return ToolResult.err("缺少必填参数 path 或 old_str")
        let newStr = getString(args, "new_str")
        let filePath = Path(path)
        if (!exists(filePath)) {
            return ToolResult.err("文件不存在: ${path}")
        }
        try {
            let original = String.fromUtf8(File.readFrom(filePath))

            // 先尝试精确匹配
            var count = countOccurrences(original, oldStr)
            var matchContent = original
            var matchOld = oldStr
            var matchNew = newStr
            var normalized = false

            // 换行符容错：文件可能是 CRLF（Windows）而模型给出的 old_str 用 LF
            // （或相反）精确匹配失败时，将两边归一化为 LF 再匹配，避免多行
            // old_str 因 \r\n 与 \n 不一致而永远匹配不上
            if (count == 0) {
                let normContent = normalizeNewlines(original)
                let normOld = normalizeNewlines(oldStr)
                let normCount = countOccurrences(normContent, normOld)
                if (normCount > 0) {
                    count = normCount
                    matchContent = normContent
                    matchOld = normOld
                    matchNew = normalizeNewlines(newStr)
                    normalized = true
                }
            }

            if (count == 0) {
                return ToolResult.err("old_str 未在文件中匹配到")
            }
            if (count > 1) {
                return ToolResult.err("old_str 在文件中出现 ${count} 次，请增加上下文以唯一匹配")
            }
            var updated = matchContent.replace(matchOld, matchNew)
            // 若做过归一化且原文件本是 CRLF 风格，则恢复 CRLF 行尾，保持文件原有风格
            if (normalized && countOccurrences(original, "\r\n") > 0) {
                updated = updated.replace("\n", "\r\n")
            }
            recordFileMutation(this.journal, path, "edit_file")
            File.writeTo(filePath, updated.toArray())
            return ToolResult.ok("已编辑 ${path}（替换 1 处，新大小 ${updated.size} 字节）")
        } catch (ex: Exception) {
            return ToolResult.err("编辑失败: ${ex.message}")
        }
    }
}

// 将 CRLF 与单独的 CR 统一为 LF，用于换行符容错匹配
func normalizeNewlines(s: String): String {
    return s.replace("\r\n", "\n").replace("\r", "\n")
}

func countOccurrences(text: String, sub: String): Int64 {
    if (sub.isEmpty()) {
        return 0
    }
    var count: Int64 = 0
    var idx: Int64 = 0
    while (true) {
        match (text.indexOf(sub, idx)) {
            case Some(i) =>
                count++
                idx = i + sub.size
            case None => break
        }
    }
    return count
}
