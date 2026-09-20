import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Parsing tolerates a model that does not behave")
struct ResponseParserTests {

    private let valid = #"{"blocks": ["hallo"]}"#

    @Test("bare JSON decodes")
    func bareJSON() {
        #expect(
            ResponseParser.parseTranslate(valid)
                == .decoded(TranslateResponse(detectedSource: nil, detectedAudience: nil, blocks: ["hallo"])))
    }

    @Test("a json-tagged code fence is stripped")
    func jsonFence() {
        let raw = "```json\n\(valid)\n```"
        #expect(ResponseParser.parseTranslate(raw).blocks == ["hallo"])
    }

    @Test("a bare code fence is stripped")
    func bareFence() {
        #expect(ResponseParser.parseTranslate("```\n\(valid)\n```").blocks == ["hallo"])
    }

    @Test("prose before and after the object is ignored")
    func surroundingProse() {
        let raw = "Sure, here you go:\n\(valid)\nHope that helps!"
        #expect(ResponseParser.parseTranslate(raw).blocks == ["hallo"])
    }

    /// The case the naive first-brace-to-last-brace parser gets wrong, and the
    /// one a correction response hits most often.
    @Test("a closing brace inside a string literal does not end the object")
    func braceInsideString() {
        let raw = #"{"blocks": ["use } like this"]}"#
        #expect(ResponseParser.parseTranslate(raw).blocks == ["use } like this"])
    }

    @Test("an escaped quote inside a string literal is handled")
    func escapedQuote() {
        let raw = #"{"blocks": ["she said \"hallo\" and }"]}"#
        #expect(ResponseParser.parseTranslate(raw).blocks == [#"she said "hallo" and }"#])
    }

    @Test("an escaped backslash before a quote does not swallow the quote")
    func escapedBackslash() {
        let raw = #"{"blocks": ["ends with a backslash \\"]}"#
        #expect(ResponseParser.parseTranslate(raw).blocks == [#"ends with a backslash \"#])
    }

    @Test("nested objects decode, outermost first")
    func nestedObjects() throws {
        let raw = """
            {"corrected_blocks": ["gut"],
             "errors": [{"original":"a","corrected":"b","category":"gender",
                         "explanation_en":"x","severity":"error"}]}
            """
        let decoded = try ResponseParser.parseCorrect(raw)
        #expect(decoded.errors[0].category == .gender)
    }

    @Test("unparseable translate output degrades to the raw text")
    func translateDegrades() {
        #expect(ResponseParser.parseTranslate("I could not do that") == .degraded(raw: "I could not do that"))
    }

    @Test("valid JSON of the wrong shape also degrades for translate")
    func wrongShapeDegrades() {
        #expect(ResponseParser.parseTranslate(#"{"nonsense": 1}"#) == .degraded(raw: #"{"nonsense": 1}"#))
    }

    @Test("empty translate output degrades rather than throwing")
    func emptyTranslate() {
        #expect(ResponseParser.parseTranslate("") == .degraded(raw: ""))
    }

    @Test("unparseable correct output throws, keeping the raw output")
    func correctThrows() {
        #expect(throws: ParseFailure.self) {
            try ResponseParser.parseCorrect("I could not do that")
        }
    }

    @Test("the correct failure carries the raw output for display")
    func correctFailureCarriesRaw() {
        do {
            _ = try ResponseParser.parseCorrect("nope")
            Issue.record("expected a ParseFailure")
        } catch let failure as ParseFailure {
            #expect(failure.raw == "nope")
        } catch {
            Issue.record("expected a ParseFailure, got \(error)")
        }
    }

    @Test("valid JSON of the wrong shape throws for correct, rather than inventing changes")
    func correctWrongShapeThrows() {
        #expect(throws: ParseFailure.self) {
            try ResponseParser.parseCorrect(#"{"blocks": ["not a correction"]}"#)
        }
    }

    @Test("no opening brace at all yields nothing to extract")
    func noBrace() {
        #expect(ResponseParser.extractJSONObject(from: "no json here") == nil)
    }

    @Test("an unterminated object yields nothing rather than a partial parse")
    func unterminated() {
        #expect(ResponseParser.extractJSONObject(from: #"{"blocks": ["a""#) == nil)
    }

    @Test("an optional field left out still decodes")
    func optionalMissing() {
        #expect(ResponseParser.parseTranslate(valid).detectedAudience == nil)
    }
}

/// Reading helpers so the assertions above stay about behaviour.
extension ParseOutcome where Value == TranslateResponse {
    fileprivate var blocks: [String] {
        if case .decoded(let response) = self { return response.blocks }
        return []
    }
    fileprivate var detectedAudience: String? {
        if case .decoded(let response) = self { return response.detectedAudience }
        return nil
    }
}
