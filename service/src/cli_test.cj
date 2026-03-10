package cangjiecoder

import std.collection.*
import cangjiecoder.common.*

@Test
class CliArgoptTest {
    @TestCase
    func buildAppConfigUsesDefaultsWhenNoOptions() {
        let options = HashMap<String, String>()
        let config = buildAppConfig(options)
        @Expect(!config.workspaceRoot.isEmpty())
        @Expect(!config.serviceRoot.isEmpty())
    }

    @TestCase
    func nonOptionAtReturnsFallbackOnOutOfBounds() {
        let args: Array<String> = ["mcp-stdio"]
        @Expect(nonOptionAt(args, 0), "mcp-stdio")
        @Expect(nonOptionAt(args, 1), "")
        @Expect(nonOptionAt(args, 99), "")
    }

    @TestCase
    func subcommandRegistryIncludesMcpStdio() {
        let registry = buildSubcommandRegistry()
        @Expect(registry.contains("mcp-stdio"))
        @Expect(registry.contains("help"))
        @Expect(registry.contains("skills"))
        @Expect(registry.contains("skills-search"))
        @Expect(registry.contains("examples"))
        @Expect(registry.contains("analyze"))
        @Expect(registry.contains("create-file"))
        @Expect(registry.contains("lsp-status"))
    }

    @TestCase
    func subcommandRegistryDoesNotIncludeServe() {
        let registry = buildSubcommandRegistry()
        @Expect(!registry.contains("serve"))
    }
}
