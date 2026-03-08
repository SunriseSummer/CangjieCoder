package cangjiecoder

import std.collection.*
import std.fs.*

class SkillRegistry {
    let skills = ArrayList<SkillRecord>()

    public init(serviceRoot: String) {
        let skillsRoot = resolveBundledPath(serviceRoot, ".github/skills")
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
        let tokens = normalized.split(" ", removeEmpty: true)
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

func scoreSkill(skill: SkillRecord, normalized: String, tokens: Array<String>): Int64 {
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

func parseSkill(path: String): SkillRecord {
    let content = readTextFile(path)
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
