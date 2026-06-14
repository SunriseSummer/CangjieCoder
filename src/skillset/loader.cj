package cangjiecoder.skillset

import std.collection.*
import std.fs.*

/**
 * Skills 加载器：扫描目标项目目录下的 `.agents/skills/`
 *
 * 期望的 Skill 目录结构：
 *   <project>/.agents/skills/
 *     └── <skill-name>/
 *         └── SKILL.md   # 必须，且头部需要 YAML frontmatter 包含 name 和 description
 *
 * SKILL.md 文件格式：
 *   ---
 *   name: <skill-name>
 *   description: "<skill-description>"
 *   ---
 *   <content>
 *
 * 只有同时包含 name 和 description 的 SKILL.md 才会被识别为有效 Skill
 * README.md 和单文件 .md 不再被识别
 *
 * 加载后会作为系统提示的一部分注入到对话上下文中，
 * 以提供项目特定的指引（约定、领域知识、操作步骤等）
 */

public class Skill {
    public let name: String
    public let description: String
    public let path: String
    public let content: String

    public init(name: String, description: String, path: String, content: String) {
        this.name = name
        this.description = description
        this.path = path
        this.content = content
    }
}

/**
 * SkillSummary：仅包含 name + description + 目录路径，不加载正文
 * 用于初始化时列出可用 Skills，由 AI 按需通过 use_skill 工具加载
 */
public class SkillSummary {
    public let name: String
    public let description: String
    public let dirPath: String  // Skill 目录的绝对路径

    public init(name: String, description: String, dirPath: String) {
        this.name = name
        this.description = description
        this.dirPath = dirPath
    }
}

// YAML frontmatter 解析结果
public struct SkillFrontmatter {
    public let name: String
    public let description: String
    public let body: String

    public init(name: String, description: String, body: String) {
        this.name = name
        this.description = description
        this.body = body
    }
}

// 解析 SKILL.md 的 YAML frontmatter，提取 name 和 description
// 如果文件不以 "---" 开头，或缺少 name/description，返回 None
public func parseFrontmatter(raw: String): ?SkillFrontmatter {
    let trimmed = raw.trimStart(" \t\r\n")
    if (!trimmed.startsWith("---")) {
        return None
    }
    // afterFirst 是开头 "---" 之后的所有内容
    let afterFirst = trimmed[3..]
    // 找第二个 "---" 分隔符：必须出现在行首（即前面是换行符）
    // 以避免误匹配 YAML 值中包含的 "---" 文本
    let closeIdx = findLineStartDashes(afterFirst)
    match (closeIdx) {
        case None => return None
        case Some(ci) =>
            let yamlBlock = afterFirst[..ci].trimAscii()
            let body = afterFirst[ci + 3..].trimStart(" \t\r\n")
            var name = ""
            var description = ""
            // 简易 YAML 行解析
            for (line in yamlBlock.split("\n")) {
                let trimmed = line.trimAscii()
                if (trimmed.startsWith("name:")) {
                    name = stripYamlValue(trimmed[5..])
                } else if (trimmed.startsWith("description:")) {
                    description = stripYamlValue(trimmed[12..])
                }
            }
            if (name.isEmpty() || description.isEmpty()) {
                return None
            }
            return Some(SkillFrontmatter(name, description, body))
    }
}

/**
 * 在 afterFirst 中查找行首出现的 "---" 分隔符
 * 返回 "---" 起始的字节索引（即紧跟在 '\n' 之后的位置）
 * 若 afterFirst 本身以 "---" 开头（即开头 `---` 后紧跟 `---`），也认为匹配
 */
func findLineStartDashes(s: String): ?Int64 {
    // 若开头就是 "---"（紧跟开始标记后无间隔），直接命中
    if (s.startsWith("---")) {
        return Some(Int64(0))
    }
    match (s.indexOf("\n---")) {
        case Some(i) =>
            // i 是 '\n' 的位置，"---" 从 i+1 开始
            return Some(i + 1)
        case None => return None
    }
}

// 去除 YAML 值的引号和空白
func stripYamlValue(s: String): String {
    var value = s.trimAscii()
    if (value.size >= 2) {
        if ((value.startsWith("\"") && value.endsWith("\"")) ||
            (value.startsWith("'") && value.endsWith("'"))) {
            // 去掉首尾各一个字符（引号）
            let runes = value.toRuneArray()
            if (runes.size >= 2) {
                let inner = StringBuilder()
                for (runeIndex in 1..runes.size - 1) {
                    inner.append(runes[runeIndex].toString())
                }
                value = inner.toString()
            }
        }
    }
    return value.trimAscii()
}

public func discoverSkills(projectDir: Path): ArrayList<Skill> {
    let result = ArrayList<Skill>()
    let skillsDir = projectDir.join(".agents").join("skills")
    if (!exists(skillsDir)) {
        return result
    }
    let entries = try {
        Directory.readFrom(skillsDir)
    } catch (e: Exception) {
        eprintln("[警告] 读取 Skills 目录失败: ${skillsDir.toString()}: ${e.message}")
        return result
    }
    for (info in entries) {
        let entryPath = skillsDir.join(info.name)
        if (info.isDirectory()) {
            match (loadDirSkill(info.name, entryPath)) {
                case Some(s) => result.add(s)
                case None => ()
            }
        }
        // 不再加载单文件 .md
    }
    return result
}

/**
 * discoverSkillSummaries: 仅读取 SKILL.md 的 frontmatter（name + description），
 * 不加载正文用于初始化时在系统提示中列出可用 Skills 目录，
 * 由 AI 在迭代过程中按需通过 use_skill 工具加载完整内容
 */
public func discoverSkillSummaries(projectDir: Path): ArrayList<SkillSummary> {
    let result = ArrayList<SkillSummary>()
    let skillsDir = projectDir.join(".agents").join("skills")
    if (!exists(skillsDir)) {
        return result
    }
    let entries = try {
        Directory.readFrom(skillsDir)
    } catch (e: Exception) {
        eprintln("[警告] 读取 Skills 目录失败: ${skillsDir.toString()}: ${e.message}")
        return result
    }
    for (info in entries) {
        let entryPath = skillsDir.join(info.name)
        if (info.isDirectory()) {
            let skillFile = entryPath.join("SKILL.md")
            if (exists(skillFile)) {
                if (let Some(raw) <- readFileText(skillFile)) {
                    match (parseFrontmatter(raw)) {
                        case Some(fm) =>
                            result.add(SkillSummary(fm.name, fm.description, entryPath.toString()))
                        case None =>
                            eprintln("[警告] SKILL.md 缺少有效的 name/description frontmatter: ${skillFile.toString()}")
                    }
                }
            }
        }
    }
    return result
}

/**
 * loadSkillContent: 按 Skill 目录路径加载完整的 SKILL.md 正文
 * 返回 (name, body) 元组，失败返回 None
 */
public func loadSkillContent(dirPath: String): ?(String, String) {
    let skillFile = Path(dirPath).join("SKILL.md")
    if (!exists(skillFile)) {
        return None
    }
    let raw = readFileText(skillFile) ?? return None
    match (parseFrontmatter(raw)) {
        case Some(fm) => return Some((fm.name, fm.body))
        case None => return None
    }
}

func loadDirSkill(_: String, dirPath: Path): ?Skill {
    // 只扫描 SKILL.md（大小写精确匹配）
    let skillFile = dirPath.join("SKILL.md")
    if (!exists(skillFile)) {
        return None
    }
    let raw = readFileText(skillFile) ?? return None
    match (parseFrontmatter(raw)) {
        case Some(fm) =>
            return Some(Skill(fm.name, fm.description, skillFile.toString(), fm.body))
        case None =>
            eprintln("[警告] SKILL.md 缺少有效的 name/description frontmatter: ${skillFile.toString()}")
            return None
    }
}

func readFileText(p: Path): ?String {
    let bytes = try {
        File.readFrom(p)
    } catch (_: Exception) {
        return None
    }
    try {
        Some(String.fromUtf8(bytes))
    } catch (_: Exception) {
        None
    }
}
