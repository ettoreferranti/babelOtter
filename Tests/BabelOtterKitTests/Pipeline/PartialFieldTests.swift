import Testing

@testable import BabelOtterKit

@Suite("A string field read from a reply that is still arriving")
struct PartialFieldTests {

    private func read(_ partial: String) -> String? {
        PartialField.string(named: "detected_audience", in: partial)
    }

    @Test("a complete value is read before the rest of the reply arrives")
    func complete() {
        #expect(read(#"{"detected_source": "en", "detected_audience": "students", "blocks": ["Hal"#) == "students")
    }

    @Test("a value still arriving is not read")
    func cutOff() {
        #expect(read(#"{"detected_audience": "stud"#) == nil)
        #expect(read(#"{"detected_audience""#) == nil)
        #expect(read(#"{"detected_audience": "#) == nil)
    }

    @Test("escapes are decoded")
    func escaped() {
        #expect(read(#"{"detected_audience": "a\"b", "#) == "a\"b")
    }

    @Test("an absent field is nil")
    func absent() {
        #expect(read(#"{"blocks": ["x"]}"#) == nil)
    }

    @Test("a field written after the blocks is still read")
    func afterBlocks() {
        #expect(read(#"{"blocks": ["x"], "detected_audience": "colleagues"}"#) == "colleagues")
    }

    @Test("space around the colon is allowed")
    func spacing() {
        #expect(read(#"{"detected_audience" :   "students""#) == "students")
    }

    @Test("a value that is not a string is nil")
    func notAString() {
        #expect(read(#"{"detected_audience": null}"#) == nil)
    }
}
