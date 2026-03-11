// 动态工作区路径管理测试：覆盖 set_root、get_root、initialize roots、workspacePath 覆盖
package cangjiecoder

import std.env.*
import std.fs.*
import cangjiecoder.common.*
import cangjiecoder.json.*
import cangjiecoder.mcp.*
import cangjiecoder.tools.*
import stdx.encoding.json.*

@Test
class WorkspaceRootTest {
    // ── workspace.get_root 测试 ───────────────────────

    @TestCase
    func getRootReturnsCurrentWorkspace() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.get_root\",\"arguments\":{}}}")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains("\"workspaceRoot\""))
                @Expect(payload.contains(getWorkingDirectory().toString()))
            case None =>
                @Expect(false)
        }
    }

    // ── workspace.set_root 测试 ───────────────────────

    @TestCase
    func setRootUpdatesWorkspace() {
        let tmpDir = Directory.createTemp(Path("/tmp"))
        let tmpPath = canonicalize(tmpDir).toString()
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.set_root\",\"arguments\":{\"path\":\"${tmpPath}\"}}}")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains("\"workspaceRoot\""))
                @Expect(payload.contains(tmpPath))
                // 验证 runtime 的 workspaceRoot 已更新
                @Expect(runtime.workspaceRoot, tmpPath)
            case None =>
                @Expect(false)
        }
        remove(tmpDir, recursive: true)
    }

    @TestCase
    func setRootRejectsEmptyPath() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.set_root\",\"arguments\":{\"path\":\"\"}}}")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains("\"ok\":false"))
            case None =>
                @Expect(false)
        }
    }

    @TestCase
    func setRootRejectsRelativePath() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.set_root\",\"arguments\":{\"path\":\"relative/path\"}}}")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains("\"ok\":false"))
                @Expect(payload.contains("not absolute"))
            case None =>
                @Expect(false)
        }
    }

    @TestCase
    func setRootRejectsNonexistentPath() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.set_root\",\"arguments\":{\"path\":\"/nonexistent/path/12345\"}}}")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains("\"ok\":false"))
                @Expect(payload.contains("does not exist"))
            case None =>
                @Expect(false)
        }
    }

    @TestCase
    func setRootPersistsAcrossToolCalls() {
        let tmpDir = Directory.createTemp(Path("/tmp"))
        let tmpPath = canonicalize(tmpDir).toString()
        let runtime = createMcpRuntime(getWorkingDirectory().toString())

        // 先设置新的 workspace root
        runtime.handleRequest(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.set_root\",\"arguments\":{\"path\":\"${tmpPath}\"}}}")

        // 再调用 get_root 验证持久化
        let response = runtime.handleRequest(
            "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.get_root\",\"arguments\":{}}}")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains(tmpPath))
            case None =>
                @Expect(false)
        }
        remove(tmpDir, recursive: true)
    }

    // ── initialize roots 自动检测测试 ─────────────────

    @TestCase
    func initializeWithRootsUpdatesWorkspace() {
        let tmpDir = Directory.createTemp(Path("/tmp"))
        let tmpPath = canonicalize(tmpDir).toString()
        // hasExplicitRepo: false → 允许 initialize roots 覆盖
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"roots\":[{\"uri\":\"file://${tmpPath}\",\"name\":\"test\"}]}}")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains("\"CangjieCoder\""))
                // 验证 workspaceRoot 已从 roots 中更新
                @Expect(runtime.workspaceRoot, tmpPath)
            case None =>
                @Expect(false)
        }
        remove(tmpDir, recursive: true)
    }

    @TestCase
    func initializeWithExplicitRepoIgnoresRoots() {
        let tmpDir = Directory.createTemp(Path("/tmp"))
        let tmpPath = canonicalize(tmpDir).toString()
        let originalRoot = getWorkingDirectory().toString()
        // hasExplicitRepo: true → initialize roots 不覆盖
        let runtime = createMcpRuntime(originalRoot, hasExplicitRepo: true)
        runtime.handleRequest(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"roots\":[{\"uri\":\"file://${tmpPath}\",\"name\":\"test\"}]}}")
        // workspaceRoot 不应被覆盖
        @Expect(runtime.workspaceRoot, canonicalize(originalRoot).toString())
        remove(tmpDir, recursive: true)
    }

    @TestCase
    func initializeWithoutRootsKeepsDefault() {
        let originalRoot = getWorkingDirectory().toString()
        let runtime = createMcpRuntime(originalRoot)
        runtime.handleRequest(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}")
        @Expect(runtime.workspaceRoot, originalRoot)
    }

    @TestCase
    func initializeWithInvalidRootPathKeepsDefault() {
        let originalRoot = getWorkingDirectory().toString()
        let runtime = createMcpRuntime(originalRoot)
        runtime.handleRequest(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"roots\":[{\"uri\":\"file:///nonexistent/path/abc\",\"name\":\"bad\"}]}}")
        @Expect(runtime.workspaceRoot, originalRoot)
    }

    // ── workspacePath 参数覆盖测试 ────────────────────

    @TestCase
    func workspacePathOverridesDefaultRoot() {
        let tmpDir = Directory.createTemp(Path("/tmp"))
        let tmpPath = canonicalize(tmpDir).toString()
        let testFile = "${tmpPath}/test.cj"
        File.writeTo(testFile, "main() {}".toArray())

        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let response = runtime.handleRequest(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.list_files\",\"arguments\":{\"workspacePath\":\"${tmpPath}\"}}}")
        match (response) {
            case Some(payload) =>
                @Expect(payload.contains("test.cj"))
            case None =>
                @Expect(false)
        }
        // 验证 runtime 的 workspaceRoot 不被修改（仅本次调用覆盖）
        @Expect(runtime.workspaceRoot != tmpPath)
        remove(tmpDir, recursive: true)
    }

    @TestCase
    func workspacePathIgnoresInvalidPath() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let originalRoot = runtime.workspaceRoot
        // 无效路径应回退到默认工作区
        let response = runtime.handleRequest(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.get_root\",\"arguments\":{\"workspacePath\":\"/nonexistent/path\"}}}")
        @Expect(runtime.workspaceRoot, originalRoot)
    }

    @TestCase
    func workspacePathIgnoresRelativePath() {
        let runtime = createMcpRuntime(getWorkingDirectory().toString())
        let originalRoot = runtime.workspaceRoot
        // 相对路径应被忽略
        let response = runtime.handleRequest(
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"workspace.get_root\",\"arguments\":{\"workspacePath\":\"relative\"}}}")
        @Expect(runtime.workspaceRoot, originalRoot)
    }

    // ── fileUriToPath 测试 ────────────────────────────

    @TestCase
    func fileUriToPathParsesStandardUri() {
        let result = fileUriToPath("file:///home/user/project")
        match (result) {
            case Some(path) => @Expect(path, "/home/user/project")
            case None => @Expect(false)
        }
    }

    @TestCase
    func fileUriToPathRejectsNonFileUri() {
        let result = fileUriToPath("http://example.com")
        match (result) {
            case Some(_) => @Expect(false)
            case None => @Expect(true)
        }
    }

    @TestCase
    func fileUriToPathRejectsEmptyString() {
        let result = fileUriToPath("")
        match (result) {
            case Some(_) => @Expect(false)
            case None => @Expect(true)
        }
    }

    // ── 工具定义覆盖测试 ─────────────────────────────

    @TestCase
    func toolDefinitionsIncludeSetAndGetRoot() {
        let json = toolDefinitionsJson()
        @Expect(json.contains("workspace.set_root"))
        @Expect(json.contains("workspace.get_root"))
    }

    @TestCase
    func toolRegistryIncludesSetAndGetRoot() {
        let registry = buildMcpToolRegistry()
        @Expect(registry.contains("workspace.set_root"))
        @Expect(registry.contains("workspace.get_root"))
    }
}
