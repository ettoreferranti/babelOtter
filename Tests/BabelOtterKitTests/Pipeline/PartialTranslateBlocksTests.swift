import Testing

@testable import BabelOtterKit

@Suite("A translate reply read while it is still arriving")
struct PartialTranslateBlocksTests {

    @Test("nothing before the blocks key has arrived", arguments: [
        "", "{", "{\"detected_source\": \"de\", ", "{\"blocks\"", "{\"blocks\": ", "{\"blocks\": [",
    ])
    func nothingYet(_ partial: String) {
        #expect(PartialTranslateBlocks.extract(from: partial) == [])
    }

    @Test("finished blocks and the one being written")
    func finishedAndInProgress() {
        let partial = "{\"detected_source\": \"de\", \"blocks\": [\"Hallo\", \"Wel"
        #expect(PartialTranslateBlocks.extract(from: partial) == ["Hallo", "Wel"])
    }

    @Test("a block whose opening quote just arrived is an empty block")
    func openingQuoteOnly() {
        #expect(PartialTranslateBlocks.extract(from: "{\"blocks\": [\"a\", \"") == ["a", ""])
    }

    @Test("a complete reply reads the same as the parser would")
    func complete() {
        let reply = "{\"blocks\": [\"one\", \"two\"], \"detected_audience\": \"colleagues\"}"
        #expect(PartialTranslateBlocks.extract(from: reply) == ["one", "two"])
    }

    @Test("a code fence before the object does not matter")
    func codeFence() {
        #expect(PartialTranslateBlocks.extract(from: "```json\n{\"blocks\": [\"x\"") == ["x"])
    }

    @Test("escapes are decoded")
    func escapes() {
        let partial = #"{"blocks": ["say \"hi\"\nnow\\then\ttab"]}"#
        #expect(PartialTranslateBlocks.extract(from: partial) == ["say \"hi\"\nnow\\then\ttab"])
    }

    @Test("a unicode escape is decoded, including a surrogate pair")
    func unicodeEscapes() {
        #expect(PartialTranslateBlocks.extract(from: #"{"blocks": ["caf\u00e9"]}"#) == ["caf\u{00E9}"])
        #expect(PartialTranslateBlocks.extract(from: #"{"blocks": ["\ud83e\udda6"]}"#) == ["\u{1F9A6}"])
    }

    @Test("an escape cut off mid-way is left out rather than guessed", arguments: [
        (#"{"blocks": ["ab\"#, "ab"),
        (#"{"blocks": ["ab\u00"#, "ab"),
        (#"{"blocks": ["ab\ud83e"#, "ab"),
        (#"{"blocks": ["ab\ud83e\ud"#, "ab"),
    ])
    func truncatedEscape(_ partial: String, _ expected: String) {
        #expect(PartialTranslateBlocks.extract(from: partial) == [expected])
    }

    @Test("sentinels pass through untouched")
    func sentinels() {
        let partial = "{\"blocks\": [\"\u{27E6}DNT0\u{27E7} is"
        #expect(PartialTranslateBlocks.extract(from: partial) == ["\u{27E6}DNT0\u{27E7} is"])
    }

    @Test("something that is not a string ends the read")
    func unexpectedToken() {
        #expect(PartialTranslateBlocks.extract(from: "{\"blocks\": [\"a\", 3, \"b\"]}") == ["a"])
    }
}