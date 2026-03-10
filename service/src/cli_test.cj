package cangjiecoder

import std.collection.*
import cangjiecoder.common.*

@Test
class CliArgoptTest {
    @TestCase
    func buildAppConfigUsesDefaultsWhenNoOptions() {
        let options = HashMap<String, String>()
        let config = buildAppConfig(options)
        @Expect(config.host, "127.0.0.1")
    }

    @TestCase
    func buildAppConfigReadsPortFromOptions() {
        let options = HashMap<String, String>()
        options["port"] = "9090"
        let config = buildAppConfig(options)
        @Expect(config.port, 9090)
    }

    @TestCase
    func buildAppConfigFallsBackOnInvalidPort() {
        let options = HashMap<String, String>()
        options["port"] = "not_a_number"
        let config = buildAppConfig(options)
        @Expect(config.port, 8080)
    }

    @TestCase
    func buildAppConfigReadsHostFromOptions() {
        let options = HashMap<String, String>()
        options["host"] = "0.0.0.0"
        let config = buildAppConfig(options)
        @Expect(config.host, "0.0.0.0")
    }

    @TestCase
    func nonOptionAtReturnsFallbackOnOutOfBounds() {
        let args: Array<String> = ["serve"]
        @Expect(nonOptionAt(args, 0), "serve")
        @Expect(nonOptionAt(args, 1), "")
        @Expect(nonOptionAt(args, 99), "")
    }
}
