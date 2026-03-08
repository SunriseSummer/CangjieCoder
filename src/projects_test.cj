package cangjiecoder

import std.env.*
import std.fs.*

@Test
class ProjectBootstrapTest {
    @TestCase
    func listExamplesIncludesJsonParser() {
        let projects = listExampleProjects(getWorkingDirectory().toString())
        @Expect(projects.size > 0)
        @Expect(projects[0].id, "json_parser")
    }

    @TestCase
    func bootstrapJsonParserCopiesTemplate() {
        let repoRoot = getWorkingDirectory().toString()
        let targetRoot = "${repoRoot}/target/bootstrap-json-parser-test"
        removeIfExists(targetRoot, recursive: true)

        let message = bootstrapJsonParserProject(repoRoot, "target/bootstrap-json-parser-test")
        @Expect(message.contains("Bootstrapped JsonParser example"))
        @Expect(exists("${targetRoot}/cjpm.toml"))
        @Expect(exists("${targetRoot}/src/json_parser.cj"))
        @Expect(readTextFile("${targetRoot}/src/json_parser.cj").contains("class JsonParser"))

        removeIfExists(targetRoot, recursive: true)
    }

    @TestCase
    func extractLspBodiesParsesFramedResponses() {
        let payload = "${encodeLspFrame("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"capabilities\":{}}}")}${encodeLspFrame("{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":null}")}"
        let bodies = extractLspBodies(payload)
        @Expect(bodies.size, 2)
        @Expect(bodies[0].contains("\"capabilities\""))
    }
}
