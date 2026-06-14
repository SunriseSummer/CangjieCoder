package cangjiecoder.skillset

import std.collection.*
import std.fs.*
import std.sync.*
import std.time.*
import std.unittest.*
import std.unittest.testmacro.*

let g_skillSandboxCounter = AtomicInt64(0)

func newProjectDir(): Path {
    let counter = g_skillSandboxCounter.fetchAdd(1) + 1
    let nanos = DateTime.nowUTC().toUnixTimeStamp().toNanoseconds()
    let root = Path("/tmp/cangjiecoder_skillset_${nanos}_${counter}")
    Directory.create(root, recursive: true)
    return root
}

func cleanup(p: Path) {
    if (exists(p)) {
        try { remove(p, recursive: true) } catch (_: Exception) {}
    }
}

func writeFile(p: Path, content: String) {
    let parent = p.parent
    if (!parent.toString().isEmpty() && !exists(parent)) {
        Directory.create(parent, recursive: true)
    }
    File.writeTo(p, content.toArray())
}

// ---- Frontmatter 解析单元测试 ----

@Test
class ParseFrontmatterTests {
    @TestCase
    func validFrontmatter() {
        let raw = "---\nname: my-skill\ndescription: \"A test skill\"\n---\n# Body\nHello"
        match (parseFrontmatter(raw)) {
            case Some(fm) =>
                @Expect(fm.name, "my-skill")
                @Expect(fm.description, "A test skill")
                @Expect(fm.body.contains("# Body"), true)
                @Expect(fm.body.contains("Hello"), true)
            case None =>
                @Fail("expected Some, got None")
        }
    }

    @TestCase
    func validWithSingleQuotes() {
        let raw = "---\nname: 'quoted-name'\ndescription: 'quoted desc'\n---\nbody"
        match (parseFrontmatter(raw)) {
            case Some(fm) =>
                @Expect(fm.name, "quoted-name")
                @Expect(fm.description, "quoted desc")
            case None =>
                @Fail("expected Some, got None")
        }
    }

    @TestCase
    func validWithoutQuotes() {
        let raw = "---\nname: bare-name\ndescription: bare description here\n---\nbody"
        match (parseFrontmatter(raw)) {
            case Some(fm) =>
                @Expect(fm.name, "bare-name")
                @Expect(fm.description, "bare description here")
            case None =>
                @Fail("expected Some, got None")
        }
    }

    @TestCase
    func missingName() {
        let raw = "---\ndescription: \"only desc\"\n---\nbody"
        @Expect(parseFrontmatter(raw).isNone(), true)
    }

    @TestCase
    func missingDescription() {
        let raw = "---\nname: only-name\n---\nbody"
        @Expect(parseFrontmatter(raw).isNone(), true)
    }

    @TestCase
    func noFrontmatter() {
        let raw = "# Just markdown\nNo frontmatter here"
        @Expect(parseFrontmatter(raw).isNone(), true)
    }

    @TestCase
    func emptyFrontmatter() {
        let raw = "---\n---\nbody"
        @Expect(parseFrontmatter(raw).isNone(), true)
    }

    @TestCase
    func noClosingDelimiter() {
        let raw = "---\nname: x\ndescription: y\nno closing"
        @Expect(parseFrontmatter(raw).isNone(), true)
    }

    @TestCase
    func emptyNameValue() {
        let raw = "---\nname: \ndescription: valid\n---\nbody"
        @Expect(parseFrontmatter(raw).isNone(), true)
    }

    @TestCase
    func emptyDescriptionValue() {
        let raw = "---\nname: valid\ndescription: \n---\nbody"
        @Expect(parseFrontmatter(raw).isNone(), true)
    }

    @TestCase
    func chineseFrontmatter() {
        let raw = "---\nname: cangjie-std\ndescription: \"提供仓颉语言标准库文档\"\n---\n内容"
        match (parseFrontmatter(raw)) {
            case Some(fm) =>
                @Expect(fm.name, "cangjie-std")
                @Expect(fm.description, "提供仓颉语言标准库文档")
                @Expect(fm.body, "内容")
            case None =>
                @Fail("expected Some, got None")
        }
    }

    @TestCase
    func dashesInYamlValueDoNotBreakParsing() {
        // description 值中包含 "---"，不应被误识为 frontmatter 闭合分隔符
        let raw = "---\nname: test-skill\ndescription: \"Use --- for separators\"\n---\nBody text"
        match (parseFrontmatter(raw)) {
            case Some(fm) =>
                @Expect(fm.name, "test-skill")
                @Expect(fm.description, "Use --- for separators")
                @Expect(fm.body, "Body text")
            case None =>
                @Fail("expected Some, got None for dashes-in-value")
        }
    }
}

// ---- Skill 发现单元测试 ----

@Test
class DiscoverSkillsTests {
    @TestCase
    func emptyWhenNoSkillsDir() {
        let root = newProjectDir()
        try {
            @Expect(discoverSkills(root).size, 0)
        } finally {
            cleanup(root)
        }
    }

    @TestCase
    func loadsSkillWithValidFrontmatter() {
        let root = newProjectDir()
        try {
            let skillMd = "---\nname: my-skill\ndescription: \"A test skill\"\n---\n# Skill body"
            let skillPath = root.join(".agents").join("skills").join("my-skill").join("SKILL.md")
            writeFile(skillPath, skillMd)
            let skills = discoverSkills(root)
            @Expect(skills.size, 1)
            @Expect(skills[0].name, "my-skill")
            @Expect(skills[0].description, "A test skill")
            @Expect(skills[0].content.contains("Skill body"), true)
        } finally {
            cleanup(root)
        }
    }

    @TestCase
    func rejectsSkillMdWithoutFrontmatter() {
        let root = newProjectDir()
        try {
            let skillPath = root.join(".agents").join("skills").join("bad").join("SKILL.md")
            writeFile(skillPath, "# No frontmatter\nJust content")
            let skills = discoverSkills(root)
            @Expect(skills.size, 0)
        } finally {
            cleanup(root)
        }
    }

    @TestCase
    func rejectsSkillMdWithoutDescription() {
        let root = newProjectDir()
        try {
            let skillPath = root.join(".agents").join("skills").join("no-desc").join("SKILL.md")
            writeFile(skillPath, "---\nname: no-desc\n---\ncontent")
            let skills = discoverSkills(root)
            @Expect(skills.size, 0)
        } finally {
            cleanup(root)
        }
    }

    @TestCase
    func ignoresReadmeMd() {
        let root = newProjectDir()
        try {
            let readmePath = root.join(".agents").join("skills").join("legacy").join("README.md")
            writeFile(readmePath, "readme content")
            let skills = discoverSkills(root)
            @Expect(skills.size, 0)
        } finally {
            cleanup(root)
        }
    }

    @TestCase
    func ignoresSingleFileMd() {
        let root = newProjectDir()
        try {
            writeFile(root.join(".agents").join("skills").join("solo.md"), "solo body")
            let skills = discoverSkills(root)
            @Expect(skills.size, 0)
        } finally {
            cleanup(root)
        }
    }

    @TestCase
    func skipsDirsWithoutSkillMd() {
        let root = newProjectDir()
        try {
            let bad = root.join(".agents").join("skills").join("orphan").join("notes.txt")
            writeFile(bad, "ignored")
            let goodMd = "---\nname: good\ndescription: \"kept\"\n---\nkept"
            let good = root.join(".agents").join("skills").join("good").join("SKILL.md")
            writeFile(good, goodMd)
            let skills = discoverSkills(root)
            @Expect(skills.size, 1)
            @Expect(skills[0].name, "good")
        } finally {
            cleanup(root)
        }
    }

    @TestCase
    func loadsMultipleValidSkills() {
        let root = newProjectDir()
        try {
            let md1 = "---\nname: alpha\ndescription: \"Alpha skill\"\n---\nalpha body"
            let md2 = "---\nname: beta\ndescription: \"Beta skill\"\n---\nbeta body"
            writeFile(root.join(".agents").join("skills").join("alpha").join("SKILL.md"), md1)
            writeFile(root.join(".agents").join("skills").join("beta").join("SKILL.md"), md2)
            let skills = discoverSkills(root)
            @Expect(skills.size, 2)
            // 收集名称
            let names = ArrayList<String>()
            for (skill in skills) { names.add(skill.name) }
            @Expect(names.contains("alpha"), true)
            @Expect(names.contains("beta"), true)
        } finally {
            cleanup(root)
        }
    }

    @TestCase
    func mixedValidAndInvalid() {
        let root = newProjectDir()
        try {
            // valid
            let validMd = "---\nname: good\ndescription: \"good desc\"\n---\ncontent"
            writeFile(root.join(".agents").join("skills").join("good").join("SKILL.md"), validMd)
            // invalid: no description
            let invalidMd = "---\nname: bad\n---\ncontent"
            writeFile(root.join(".agents").join("skills").join("bad").join("SKILL.md"), invalidMd)
            // invalid: README.md only
            writeFile(root.join(".agents").join("skills").join("legacy").join("README.md"), "readme")
            let skills = discoverSkills(root)
            @Expect(skills.size, 1)
            @Expect(skills[0].name, "good")
        } finally {
            cleanup(root)
        }
    }
}

// ---- Prompt 渲染单元测试 ----

@Test
class RenderSkillsPromptTests {
    @TestCase
    func emptyListProducesEmptyString() {
        let skills = ArrayList<Skill>()
        @Expect(renderSkillsPrompt(skills), "")
    }

    @TestCase
    func includesHeaderAndAllSkills() {
        let skills = ArrayList<Skill>()
        skills.add(Skill("alpha", "Alpha description", "/x/alpha/SKILL.md", "alpha body"))
        skills.add(Skill("beta", "Beta description", "/x/beta/SKILL.md", "beta body"))
        let out = renderSkillsPrompt(skills)
        @Expect(out.contains(SKILLS_HEADER), true)
        @Expect(out.contains("## Skill: alpha"), true)
        @Expect(out.contains("## Skill: beta"), true)
        @Expect(out.contains("Alpha description"), true)
        @Expect(out.contains("Beta description"), true)
        @Expect(out.contains("alpha body"), true)
        @Expect(out.contains("beta body"), true)
        @Expect(out.contains("/x/alpha/SKILL.md"), true)
    }

    @TestCase
    func includesDescriptionLine() {
        let skills = ArrayList<Skill>()
        skills.add(Skill("test", "Test description here", "/x/test/SKILL.md", "body"))
        let out = renderSkillsPrompt(skills)
        @Expect(out.contains("描述：Test description here"), true)
    }
}

// ---- Skill Catalog 渲染单元测试 ----

@Test
class RenderSkillCatalogTests {
    @TestCase
    func emptyListProducesEmptyString() {
        let summaries = ArrayList<SkillSummary>()
        @Expect(renderSkillCatalog(summaries), "")
    }

    @TestCase
    func includesHeaderAndAllSummaries() {
        let summaries = ArrayList<SkillSummary>()
        summaries.add(SkillSummary("alpha", "Alpha description", "/x/alpha"))
        summaries.add(SkillSummary("beta", "Beta description", "/x/beta"))
        let out = renderSkillCatalog(summaries)
        @Expect(out.contains(SKILLS_CATALOG_HEADER), true)
        @Expect(out.contains("**alpha**"), true)
        @Expect(out.contains("**beta**"), true)
        @Expect(out.contains("Alpha description"), true)
        @Expect(out.contains("Beta description"), true)
    }

    @TestCase
    func doesNotIncludeFullContent() {
        let summaries = ArrayList<SkillSummary>()
        summaries.add(SkillSummary("test", "Test desc", "/x/test"))
        let out = renderSkillCatalog(summaries)
        // Should not contain body content, just name + description
        @Expect(out.contains("use_skill"), true)
        @Expect(out.contains("**test**"), true)
    }
}

// ---- SkillSummary 发现单元测试 ----

@Test
class DiscoverSkillSummariesTests {
    @TestCase
    func emptyWhenNoSkillsDir() {
        let root = newProjectDir()
        try {
            @Expect(discoverSkillSummaries(root).size, 0)
        } finally {
            cleanup(root)
        }
    }

    @TestCase
    func discoversSummariesFromValidSkills() {
        let root = newProjectDir()
        try {
            let md = "---\nname: my-skill\ndescription: \"A test skill\"\n---\n# Full body content here"
            let skillPath = root.join(".agents").join("skills").join("my-skill").join("SKILL.md")
            writeFile(skillPath, md)
            let summaries = discoverSkillSummaries(root)
            @Expect(summaries.size, 1)
            @Expect(summaries[0].name, "my-skill")
            @Expect(summaries[0].description, "A test skill")
        } finally {
            cleanup(root)
        }
    }

    @TestCase
    func loadSkillContentReturnsFull() {
        let root = newProjectDir()
        try {
            let md = "---\nname: my-skill\ndescription: \"A test skill\"\n---\n# Full body content here"
            let skillDir = root.join(".agents").join("skills").join("my-skill")
            let skillPath = skillDir.join("SKILL.md")
            writeFile(skillPath, md)
            match (loadSkillContent(skillDir.toString())) {
                case Some((name, body)) =>
                    @Expect(name, "my-skill")
                    @Expect(body.contains("Full body content"), true)
                case None =>
                    @Fail("expected Some, got None")
            }
        } finally {
            cleanup(root)
        }
    }
}

// ---- readFileText Option 机制单元测试 ----

@Test
class ReadFileTextOptionTests {
    @TestCase
    func returnsContentForValidFile() {
        let root = newProjectDir()
        try {
            let filePath = root.join("test.txt")
            let content = "hello world"
            File.writeTo(filePath, content.toArray())
            match (readFileText(filePath)) {
                case Some(result) =>
                    @Expect(result, content)
                case None =>
                    @Fail("expected Some, got None")
            }
        } finally {
            cleanup(root)
        }
    }

    @TestCase
    func returnsNoneForNonexistentFile() {
        let result = readFileText(Path("/tmp/nonexistent_skill_file_12345.md"))
        @Expect(result.isNone(), true)
    }

    @TestCase
    func returnsNoneForInvalidUtf8() {
        let root = newProjectDir()
        try {
            let filePath = root.join("bad.bin")
            let badBytes: Array<Byte> = [0x80u8, 0xFEu8, 0xFFu8]
            File.writeTo(filePath, badBytes)
            let result = readFileText(filePath)
            @Expect(result.isNone(), true)
        } finally {
            cleanup(root)
        }
    }

    @TestCase
    func loadSkillContentReturnsNoneForUnreadableDir() {
        // 验证 ?? return None 行为：目录不含 SKILL.md 时返回 None
        let result = loadSkillContent("/tmp/nonexistent_dir_12345")
        @Expect(result.isNone(), true)
    }

    @TestCase
    func loadSkillContentReturnsNoneForInvalidUtf8Skill() {
        // 验证 ?? return None 行为：SKILL.md 包含非法 UTF-8 时返回 None
        let root = newProjectDir()
        try {
            let skillDir = root.join("bad-skill")
            Directory.create(skillDir, recursive: true)
            let skillFile = skillDir.join("SKILL.md")
            let badBytes: Array<Byte> = [0x80u8, 0xFEu8, 0xFFu8]
            File.writeTo(skillFile, badBytes)
            let result = loadSkillContent(skillDir.toString())
            @Expect(result.isNone(), true)
        } finally {
            cleanup(root)
        }
    }

    @TestCase
    func discoverSkillSummariesSkipsUnreadableSkill() {
        // 验证 if-let Some(raw) 行为：无法读取的 SKILL.md 被跳过
        let root = newProjectDir()
        try {
            let skillsDir = root.join(".agents").join("skills")
            // 有效 Skill
            let goodMd = "---\nname: good\ndescription: \"Good skill\"\n---\ncontent"
            writeFile(skillsDir.join("good").join("SKILL.md"), goodMd)
            // 无效 UTF-8 Skill
            let badDir = skillsDir.join("bad")
            Directory.create(badDir, recursive: true)
            let badBytes: Array<Byte> = [0x80u8, 0xFEu8, 0xFFu8]
            File.writeTo(badDir.join("SKILL.md"), badBytes)
            let summaries = discoverSkillSummaries(root)
            @Expect(summaries.size, 1)
            @Expect(summaries[0].name, "good")
        } finally {
            cleanup(root)
        }
    }
}
