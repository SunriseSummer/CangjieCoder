// 技能注册表：技能加载、搜索、排名
package cangjiecoder.skills

import std.collection.*
import std.fs.*

public struct SkillRecord {
    public SkillRecord(public let id: String,
                       public let name: String,
                       public let description: String,
                       public let preview: String,
                       public let path: String) {}
}

public class SkillRegistry {
    let skills = ArrayList<SkillRecord>()

    public init(serviceRoot: String) {
        let skillsRoot = skillsResolveBundledPath(serviceRoot, ".github/skills")
        if (exists(skillsRoot)) {
            loadSkillDirectory(skillsRoot)
        }
    }

    public func list(limit!: Int64 = 200): Array<SkillRecord> {
        let results = ArrayList<SkillRecord>()
        for (skill in skills) {
            results.add(skill)
            if (results.size >= limit) {
                break
            }
        }
        return results.toArray()
    }

    public func search(query: String, limit!: Int64 = 8): Array<SkillRecord> {
        if (query.trimAscii().isEmpty()) {
            return list(limit: limit)
        }
        let normalized = query.toAsciiLower().trimAscii()
        let tokens = tokenizeQuery(normalized)
        let rankedSkills = ArrayList<SkillRecord>()
        let rankedScores = ArrayList<Int64>()
        for (skill in skills) {
            let score = scoreSkill(skill, normalized, tokens)
            if (score <= 0) {
                continue
            }
            var inserted = false
            for (idx in 0..rankedScores.size) {
                if (idx == rankedScores.size || score > rankedScores[idx]) {
                    rankedScores.add(score, at: idx)
                    rankedSkills.add(skill, at: idx)
                    inserted = true
                    break
                }
            }
            if (!inserted) {
                rankedScores.add(score)
                rankedSkills.add(skill)
            }
        }

        let results = ArrayList<SkillRecord>()
        for (skill in rankedSkills) {
            results.add(skill)
            if (results.size >= limit) {
                return results.toArray()
            }
        }
        return results.toArray()
    }

    public func buildPromptContext(query: String, limit!: Int64 = 3): String {
        let matches = search(query, limit: limit)
        if (matches.isEmpty()) {
            return ""
        }
        let blocks = ArrayList<String>()
        for (skill in matches) {
            blocks.add("[${skill.id}] ${skill.description}\n${skill.preview}")
        }
        return String.join(blocks.toArray(), delimiter: "\n\n")
    }

    private func loadSkillDirectory(path: String): Unit {
        for (entry in Directory.readFrom(path)) {
            let entryPath = entry.path.toString()
            if (entry.isDirectory()) {
                loadSkillDirectory(entryPath)
            } else if (entry.name == "SKILL.md") {
                skills.add(parseSkill(entryPath))
            }
        }
    }
}

// 对搜索查询进行分词，支持中英文混合。
// 先按空格和常见中文连接词（和/或/与/的/在/中/用/把/了/是）拆分，
// 再对纯中文片段按 2 字滑动窗口切分为更小的关键词。
public func tokenizeQuery(normalized: String): Array<String> {
    // 第一步：按空格拆分
    let spaceParts = normalized.split(" ", removeEmpty: true)
    let segments = ArrayList<String>()
    let particles = ["和", "或", "与", "的", "在", "中", "用", "把", "了", "是",
                     "如何", "怎么", "什么", "哪些", "可以", "使用", "进行",
                     "以及", "并且", "通过", "关于"]
    for (part in spaceParts) {
        // 在每个 part 中，尝试按中文虚词进一步拆分
        var current = part
        for (p in particles) {
            current = current.replace(p, " ")
        }
        for (sub in current.split(" ", removeEmpty: true)) {
            segments.add(sub)
        }
    }
    // 第二步：对较长片段生成子词
    let tokens = ArrayList<String>()
    for (seg in segments) {
        tokens.add(seg)
        // 对长度 > 2 字节的中文片段，按 2 字符滑动窗口追加子词
        let runes = seg.toRuneArray()
        if (runes.size > 2) {
            for (i in 0..runes.size - 1) {
                let bigram = "${runes[i]}${runes[i + 1]}"
                if (!tokens.contains(bigram) && bigram != seg) {
                    tokens.add(bigram)
                }
            }
        }
    }
    return tokens.toArray()
}

public func scoreSkill(skill: SkillRecord, normalized: String, tokens: Array<String>): Int64 {
    let idText = "${skill.id} ${skill.name}".toAsciiLower()
    let descriptionText = skill.description.toAsciiLower()
    let previewText = skill.preview.toAsciiLower()
    var score = 0

    if (idText.contains(normalized)) {
        score += 100
    }
    if (descriptionText.contains(normalized)) {
        score += 40
    }
    if (previewText.contains(normalized)) {
        score += 10
    }

    for (token in tokens) {
        let keyword = token.trimAscii()
        if (keyword.size < 2) {
            continue
        }
        if (idText.contains(keyword)) {
            score += 24
        }
        if (descriptionText.contains(keyword)) {
            score += 8
        }
        if (previewText.contains(keyword)) {
            score += 2
        }
    }
    return score
}

public func parseSkill(path: String): SkillRecord {
    let content = skillsReadTextFile(path)
    let normalizedPath = path.replace("\\", "/")
    let segments = normalizedPath.split("/", removeEmpty: true)
    let skillId = if (segments.size >= 2) { segments[segments.size - 2] } else { normalizedPath }

    var name = skillId
    var description = ""
    var inFrontMatter = false
    var seenFrontMatter = false
    let previewLines = ArrayList<String>()

    for (line in content.lines()) {
        let trimmed = line.trimAscii()
        if (!seenFrontMatter && trimmed == "---") {
            seenFrontMatter = true
            inFrontMatter = true
            continue
        }
        if (inFrontMatter && trimmed == "---") {
            inFrontMatter = false
            continue
        }
        if (inFrontMatter) {
            if (trimmed.startsWith("name:")) {
                name = trimmed.removePrefix("name:").trimAscii().replace("\"", "")
            } else if (trimmed.startsWith("description:")) {
                description = trimmed.removePrefix("description:").trimAscii().replace("\"", "")
            }
            continue
        }
        if (!trimmed.isEmpty() && !trimmed.startsWith("#") && previewLines.size < 6) {
            previewLines.add(trimmed)
        }
    }

    let preview = String.join(previewLines.toArray(), delimiter: "\n")
    return SkillRecord(skillId, name, description, preview, path)
}

// 子包内部工具函数副本（避免对根包循环依赖）
func skillsReadTextFile(path: String): String {
    return String.fromUtf8(File.readFrom(path))
}

func skillsResolveBundledPath(serviceRoot: String, relativePath: String): String {
    let bundledPath = "${serviceRoot}/${relativePath}"
    if (exists(bundledPath)) {
        return canonicalize(bundledPath).toString()
    }
    let parentBundledPath = "${serviceRoot}/../${relativePath}"
    if (exists(parentBundledPath)) {
        return canonicalize(parentBundledPath).toString()
    }
    return bundledPath
}
