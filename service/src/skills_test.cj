package cangjiecoder

import std.env.*
import std.fs.*

@Test
class CangjieCoderBasicsTest {
    @TestCase
    func parseSkillMetadataFromFrontMatter() {
        let tempDir = Directory.createTemp(getTempDirectory())
        let skillDir = tempDir.join("sample")
        Directory.create(skillDir, recursive: true)
        let skillPath = skillDir.join("SKILL.md")
        File.writeTo(skillPath, "---\nname: my-skill\ndescription: demo skill\n---\n# Title\nUseful preview line\nAnother line\n".toArray())

        let skill = parseSkill(skillPath.toString())
        @Expect(skill.name, "my-skill")
        @Expect(skill.description, "demo skill")
        @Expect(skill.preview.contains("Useful preview line"))
    }

    @TestCase
    func exactReplacementRejectsAmbiguousEdits() {
        let tempDir = Directory.createTemp(getTempDirectory())
        let filePath = tempDir.join("demo.cj")
        File.writeTo(filePath, "same\nsame\n".toArray())

        let message = replaceExactText(tempDir.toString(), filePath.toString(), "same", "new")
        @Expect(message.contains("ambiguous"))
    }
}
