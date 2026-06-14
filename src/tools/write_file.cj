package cangjiecoder.tools

import std.fs.*

/**
 * `write_file` 工具：创建或覆盖文件
 *
 * - 父目录不存在时自动递归创建
 * - 默认覆盖已有文件，可通过 `overwrite=false` 仅在不存在时写入
 * - 属于敏感操作，需要审批
 */
public class WriteFileTool <: Tool {
    let journal: ?FileJournal

    public init() {
        this.journal = None
    }

    public init(journal: FileJournal) {
        this.journal = Some(journal)
    }

    public prop name: String {
        get() {
            return "write_file"
        }
    }

    public prop description: String {
        get() {
            return "创建或覆盖文本文件。父目录会被自动创建。" +
                "请确保提供完整文件内容（不要使用占位符）。"
        }
    }

    public prop parametersSchemaJson: String {
        get() {
            return ##"""
{
  "type": "object",
  "properties": {
    "path": {"type": "string", "description": "相对于当前工作目录的文件路径"},
    "content": {"type": "string", "description": "要写入的完整文件内容（UTF-8）"},
    "overwrite": {"type": "boolean", "description": "若已存在是否覆盖；默认 true", "default": true}
  },
  "required": ["path", "content"]
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
        let path = requireString(args, "path") ?? return ToolResult.err("缺少必填参数 path")
        let content = getString(args, "content")
        let overwrite = getBool(args, "overwrite", default: true)
        let filePath = Path(path)
        if (exists(filePath) && !overwrite) {
            return ToolResult.err("文件已存在且 overwrite=false: ${path}")
        }
        try {
            ensureParentDirectory(filePath)
            let isNew = !exists(filePath)
            recordFileMutation(this.journal, path, "write_file")
            File.writeTo(filePath, content.toArray())
            let action = if (isNew) {
                "已创建"
            } else {
                "已写入"
            }
            return ToolResult.ok("${action}文件: ${path} (${content.size} 字节)")
        } catch (ex: Exception) {
            return ToolResult.err("写入失败: ${ex.message}")
        }
    }
}
