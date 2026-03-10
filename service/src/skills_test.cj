package cangjiecoder

import std.env.*
import std.fs.*
import cangjiecoder.common.*
import cangjiecoder.json.*
import cangjiecoder.lsp.*
import cangjiecoder.skills.*

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

    @TestCase
    func fileBackupStoreBackupsAndRollsBack() {
        let tempDir = Directory.createTemp(getTempDirectory())
        let filePath = "${tempDir.toString()}/rollback_test.txt"
        try {
            writeTextFile(filePath, "original content")
            let store = FileBackupStore()
            store.backup(filePath)
            @Expect(store.fileCount, 1)
            @Expect(store.hasBackups())

            // 修改文件
            writeTextFile(filePath, "modified content")
            @Expect(readTextFile(filePath), "modified content")

            // 回滚
            let restored = store.rollbackAll()
            @Expect(restored.size, 1)
            @Expect(readTextFile(filePath), "original content")
            @Expect(!store.hasBackups())
        } finally {
            removeIfExists(tempDir.toString(), recursive: true)
        }
    }

    @TestCase
    func fileBackupStoreOnlyBackupsFirstVersion() {
        let tempDir = Directory.createTemp(getTempDirectory())
        let filePath = "${tempDir.toString()}/multi_backup.txt"
        try {
            writeTextFile(filePath, "v1")
            let store = FileBackupStore()
            store.backup(filePath)

            // 修改并再次备份 —— 应保持首次备份
            writeTextFile(filePath, "v2")
            store.backup(filePath)
            @Expect(store.fileCount, 1)

            writeTextFile(filePath, "v3")
            store.rollbackAll()
            @Expect(readTextFile(filePath), "v1")
        } finally {
            removeIfExists(tempDir.toString(), recursive: true)
        }
    }

    @TestCase
    func fileBackupStoreClearRemovesBackups() {
        let store = FileBackupStore()
        let tempDir = Directory.createTemp(getTempDirectory())
        let filePath = "${tempDir.toString()}/clear_test.txt"
        try {
            writeTextFile(filePath, "data")
            store.backup(filePath)
            @Expect(store.hasBackups())
            store.clear()
            @Expect(!store.hasBackups())
            @Expect(store.fileCount, 0)
        } finally {
            removeIfExists(tempDir.toString(), recursive: true)
        }
    }

    @TestCase
    func replaceExactTextCreatesBackup() {
        let tempDir = Directory.createTemp(getTempDirectory())
        let filePath = "${tempDir.toString()}/replace_backup.txt"
        try {
            writeTextFile(filePath, "hello world")
            // 使用全局备份存储，先清除
            globalBackupStore.clear()
            let message = replaceExactText(tempDir.toString(), filePath.toString(), "hello", "greetings")
            @Expect(message.startsWith("updated "))
            @Expect(readTextFile(filePath).contains("greetings"))
            // 验证备份已创建
            @Expect(globalBackupStore.hasBackups())
            // 回滚
            globalBackupStore.rollbackAll()
            @Expect(readTextFile(filePath), "hello world")
        } finally {
            globalBackupStore.clear()
            removeIfExists(tempDir.toString(), recursive: true)
        }
    }

    @TestCase
    func lspCommandCacheAvoidsRepeatedProbes() {
        // 清除缓存以测试
        clearLspCommandCache()
        let previousCommand = getVariable("CANGJIE_LSP_COMMAND")
        let previousSdkHome = getVariable("CANGJIE_SDK_HOME")
        setVariable("CANGJIE_LSP_COMMAND", "/fake/lsp/binary")
        removeVariable("CANGJIE_SDK_HOME")

        let firstResult = resolveLspCommand("/tmp")
        match (firstResult) {
            case Some(cmd) => @Expect(cmd, "/fake/lsp/binary")
            case None => @Expect(false)
        }

        // 修改环境变量后缓存应仍返回旧值
        setVariable("CANGJIE_LSP_COMMAND", "/different/binary")
        let cachedResult = resolveLspCommand("/tmp")
        match (cachedResult) {
            case Some(cmd) => @Expect(cmd, "/fake/lsp/binary")
            case None => @Expect(false)
        }

        // 清除缓存后应使用新值
        clearLspCommandCache()
        let freshResult = resolveLspCommand("/tmp")
        match (freshResult) {
            case Some(cmd) => @Expect(cmd, "/different/binary")
            case None => @Expect(false)
        }

        // 恢复环境
        match (previousCommand) {
            case Some(v) => setVariable("CANGJIE_LSP_COMMAND", v)
            case None => removeVariable("CANGJIE_LSP_COMMAND")
        }
        match (previousSdkHome) {
            case Some(v) => setVariable("CANGJIE_SDK_HOME", v)
            case None => ()
        }
        clearLspCommandCache()
        closeLspSession()
    }
}
