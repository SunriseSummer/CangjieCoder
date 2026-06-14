package cangjiecoder.tools

import std.collection.*
import std.fs.*

/**
 * `list_dir` 工具：列出目录条目
 *
 * 输出格式：每行一条「类型\t名称」记录，例如：
 *   d\tsrc/
 *   f\tREADME.md
 */

public class ListDirTool <: Tool {
    public prop name: String { get() { return "list_dir" } }

    public prop description: String {
        get() {
            return "列出指定目录下的文件与子目录（不递归）。" +
                   "默认排除 .git/target/node_modules 等常见噪声目录。"
        }
    }

    public prop parametersSchemaJson: String {
        get() {
            return ##"""
{
  "type": "object",
  "properties": {
    "path": {"type": "string", "description": "目录路径，默认当前目录", "default": "."}
  }
}
"""##
        }
    }

    public prop approval: ApprovalLevel { get() { return Safe } }

    public func execute(argumentsJson: String): ToolResult {
        let args = parseArgs(argumentsJson)
        var path = getString(args, "path")
        if (path.isEmpty()) {
            path = "."
        }
        let dirPath = Path(path)
        if (!exists(dirPath)) {
            return ToolResult.err("目录不存在: ${path}")
        }
        try {
            let entries = Directory.readFrom(dirPath)
            let names = ArrayList<(String, Bool)>()
            for (entry in entries) {
                if (isNoiseEntry(entry.name)) {
                    continue
                }
                names.add((entry.name, entry.isDirectory()))
            }
            let sb = StringBuilder()
            sb.append("// ${path} 下共 ${names.size} 项\n")
            for ((name, isDir) in names) {
                if (isDir) {
                    sb.append("d\t${name}/\n")
                } else {
                    sb.append("f\t${name}\n")
                }
            }
            return ToolResult.ok(sb.toString())
        } catch (e: Exception) {
            return ToolResult.err("读取目录失败: ${e.message}")
        }
    }
}

public func isNoiseEntry(name: String): Bool {
    return name == ".git" || name == "target" || name == "node_modules" ||
           name == ".idea" || name == ".vscode" || name == "__pycache__" ||
           name == "dist" || name == "build" || name == ".cache"
}

/**
 * 递归遍历目录树，对每个非噪声条目调用 visitor
 *
 * visitor 参数：(fsPath: Path, displayPath: String, isDir: Bool)
 * visitor 返回 true 继续，返回 false 提前终止
 */
public func walkDir(dir: Path, displayPrefix: String, visitor: (Path, String, Bool) -> Bool): Bool {
    let entries = Directory.readFrom(dir)
    for (entry in entries) {
        if (isNoiseEntry(entry.name)) {
            continue
        }
        let childFs = dir.join(entry.name)
        let childDisplay = if (displayPrefix == ".") { entry.name } else { "${displayPrefix}/${entry.name}" }
        let isDir = entry.isDirectory()
        if (!visitor(childFs, childDisplay, isDir)) {
            return false
        }
        if (isDir) {
            if (!walkDir(childFs, childDisplay, visitor)) {
                return false
            }
        }
    }
    return true
}
