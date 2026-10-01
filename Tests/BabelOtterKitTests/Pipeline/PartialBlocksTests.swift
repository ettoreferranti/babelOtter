import Testing

@testable import BabelOtterKit

@Suite("A translate reply read while it is still arriving")
struct PartialBlocksTests {

    @Test("nothing before the blocks key has arrived", arguments: [
        "", "{", "{\"detected_source\": \"de\", ", "{\"blocks\"", "{\"blocks\": ", "{\"blocks\": [",
    ])
    func nothingYet(_ partial: String) {
        #expect(PartialBlocks.extract(from: partial, key: "blocks") == [])
    }

    @Test("finished blocks and the one being written")
    func finishedAndInProgress() {
        let partial = "{\"detected_source\": \"de\", \"blocks\": [\"Hallo\", \"Wel"
        #expect(PartialBlocks.extract(from: partial, key: "blocks") == ["Hallo", "Wel"])
    }

    @Test("a block whose opening quote just arrived is an empty block")
    func openingQuoteOnly() {
        #expect(PartialBlocks.extract(from: "{\"blocks\": [\"a\", \"", key: "blocks") == ["a", ""])
    }

    @Test("a complete reply reads the same as the parser would")
    func complete() {
        let reply = "{\"blocks\": [\"one\", \"two\"], \"detected_audience\": \"colleagues\"}"
        #expect(PartialBlocks.extract(from: reply, key: "blocks") == ["one", "two"])
    }

    @Test("a code fence before the object does not matter")
    func codeFence() {
        #expect(PartialBlocks.extract(from: "```json\n{\"blocks\": [\"x\"", key: "blocks") == ["x"])
    }

    @Test("escapes are decoded")
    func escapes() {
        let partial = #"{"blocks": ["say \"hi\"\nnow\\then\ttab"]}"#
        #expect(PartialBlocks.extract(from: partial, key: "blocks") == ["say \"hi\"\nnow\\then\ttab"])
    }

    @Test("a unicode escape is decoded, including a surrogate pair")
    func unicodeEscapes() {
        #expect(PartialBlocks.extract(from: #"{"blocks": ["caf\u00e9"]}"#, key: "blocks") == ["caf\u{00E9}"])
        #expect(PartialBlocks.extract(from: #"{"blocks": ["\ud83e\udda6"]}"#, key: "blocks") == ["\u{1F9A6}"])
    }

    @Test("an escape cut off mid-way is left out rather than guessed", arguments: [
        (#"{"blocks": ["ab\"#, "ab"),
        (#"{"blocks": ["ab\u00"#, "ab"),
        (#"{"blocks": ["ab\ud83e"#, "ab"),
        (#"{"blocks": ["ab\ud83e\ud"#, "ab"),
    ])
    func truncatedEscape(_ partial: String, _ expected: String) {
        #expect(PartialBlocks.extract(from: partial, key: "blocks") == [expected])
    }

    @Test("sentinels pass through untouched")
    func sentinels() {
        let partial = "{\"blocks\": [\"\u{27E6}DNT0\u{27E7} is"
        #expect(PartialBlocks.extract(from: partial, key: "blocks") == ["\u{27E6}DNT0\u{27E7} is"])
    }

    @Test("something that is not a string ends the read")
    func unexpectedToken() {
        #expect(PartialBlocks.extract(from: "{\"blocks\": [\"a\", 3, \"b\"]}", key: "blocks") == ["a"])
    }

    @Test("any key can be read, and a different key is ignored")
    func otherKeys() {
        let partial = "{\"corrected_blocks\": [\"Ich habe\", \"mit dem Kol"
        #expect(PartialBlocks.extract(from: partial, key: "corrected_blocks") == ["Ich habe", "mit dem Kol"])
        #expect(PartialBlocks.extract(from: partial, key: "blocks") == [])
    }

    @Test("a key that is a suffix of another key does not match it")
    func keyIsWholeName() {
        #expect(PartialBlocks.extract(from: "{\"corrected_blocks\": [\"x\"]}", key: "blocks") == [])
    }
}