package cangjiecoder.tools

import std.unittest.*
import std.unittest.testmacro.*

@Test
class GlobMatchTests {
    @TestCase
    func singleStarMatchesWithinSegment() {
        @Expect(globMatch("*.cj", "main.cj"), true)
        @Expect(globMatch("*.cj", "foo.cj"), true)
        @Expect(globMatch("*.cj", "foo.txt"), false)
    }

    @TestCase
    func singleStarDoesNotMatchSlash() {
        @Expect(globMatch("*.cj", "src/main.cj"), false)
    }

    @TestCase
    func doubleStarMatchesAcrossSegments() {
        @Expect(globMatch("**/*.cj", "src/main.cj"), true)
        @Expect(globMatch("**/*.cj", "a/b/c/main.cj"), true)
        @Expect(globMatch("**/*.cj", "main.cj"), true)
        @Expect(globMatch("**/*.cj", "main.txt"), false)
    }

    @TestCase
    func doubleStarInTheMiddle() {
        @Expect(globMatch("src/**/main.cj", "src/main.cj"), true)
        @Expect(globMatch("src/**/main.cj", "src/a/main.cj"), true)
        @Expect(globMatch("src/**/main.cj", "src/a/b/main.cj"), true)
        @Expect(globMatch("src/**/main.cj", "lib/main.cj"), false)
    }

    @TestCase
    func questionMarkMatchesSingleChar() {
        @Expect(globMatch("?.txt", "a.txt"), true)
        @Expect(globMatch("?.txt", "ab.txt"), false)
        @Expect(globMatch("?.txt", "/.txt"), false)
    }

    @TestCase
    func escapesRegexSpecials() {
        @Expect(globMatch("foo.bar", "foo.bar"), true)
        @Expect(globMatch("foo.bar", "fooXbar"), false)
        @Expect(globMatch("a+b", "a+b"), true)
        @Expect(globMatch("(x)", "(x)"), true)
    }

    @TestCase
    func fullPatternRequiresFullMatch() {
        @Expect(globMatch("foo", "foobar"), false)
        @Expect(globMatch("foo", "foo"), true)
    }
}

@Test
class GlobToRegexTests {
    @TestCase
    func anchorsTheRegex() {
        let r = globToRegex("*.cj")
        @Expect(r.startsWith("^"), true)
        @Expect(r.endsWith("$"), true)
    }

    @TestCase
    func doubleStarPathExpansion() {
        // "**/*.cj" → ^.*[^/]*\.cj$
        let r = globToRegex("**/*.cj")
        @Expect(r.contains(".*"), true)
        @Expect(r.contains("[^/]*"), true)
        @Expect(r.contains("\\."), true)
    }
}
