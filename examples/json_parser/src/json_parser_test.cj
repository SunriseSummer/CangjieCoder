package json_parser

@Test
class JsonParserExampleTest {
    @TestCase
    func parseObjectAndArray() {
        let parsed = parseJson(##"{"name":"demo","items":[1,2,false,null]}"##)
        @Expect(parsed.render(), ##"{"name":"demo","items":[1.000000,2.000000,false,null]}"##)
    }

    @TestCase
    func invalidJsonThrows() {
        @ExpectThrows[JsonParseException](parseJson("{"))
    }
}
