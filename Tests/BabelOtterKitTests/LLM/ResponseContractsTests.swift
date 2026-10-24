import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Response contracts match spec §7")
struct ResponseContractsTests {

    private let decoder = JSONDecoder.responseContract

    @Test("the translate example from the spec decodes")
    func translateExample() throws {
        let json = #"{ "detected_source": "en", "detected_audience": "colleagues", "blocks": ["hallo"] }"#
        let decoded = try decoder.decode(TranslateResponse.self, from: Data(json.utf8))
        #expect(decoded.detectedSource == "en")
        #expect(decoded.detectedAudience == "colleagues")
        #expect(decoded.blocks == ["hallo"])
    }

    @Test("the audience evidence decodes when present")
    func audienceEvidence() throws {
        let json = #"{"detected_audience": "students", "audience_evidence": "Dear students", "blocks": ["a"]}"#
        let decoded = try decoder.decode(TranslateResponse.self, from: Data(json.utf8))
        #expect(decoded.audienceEvidence == "Dear students")
        let without = try decoder.decode(TranslateResponse.self, from: Data(#"{"blocks": ["a"]}"#.utf8))
        #expect(without.audienceEvidence == nil)
    }

    @Test("a wrongly typed optional field is dropped, not the whole reply")
    func wrongTypedOptionalField() throws {
        let json = #"{"detected_source": 1, "detected_audience": ["students"], "audience_evidence": ["Dear"], "blocks": ["a"]}"#
        let decoded = try decoder.decode(TranslateResponse.self, from: Data(json.utf8))
        #expect(decoded.blocks == ["a"])
        #expect(decoded.detectedSource == nil)
        #expect(decoded.detectedAudience == nil)
        #expect(decoded.audienceEvidence == nil)
    }

    @Test("a translate response missing both optional fields still decodes")
    func optionalFieldsAbsent() throws {
        let decoded = try decoder.decode(
            TranslateResponse.self, from: Data(#"{"blocks": ["a"]}"#.utf8))
        #expect(decoded.detectedSource == nil)
        #expect(decoded.detectedAudience == nil)
    }

    @Test("a translate response without blocks fails, because there is no result")
    func blocksAreRequired() {
        #expect(throws: (any Error).self) {
            try decoder.decode(TranslateResponse.self, from: Data(#"{"detected_source":"en"}"#.utf8))
        }
    }

    @Test("the correct example from the spec decodes, including the taxonomy")
    func correctExample() throws {
        let json = """
            { "corrected_blocks": ["Das ist gut"],
              "errors": [{ "original": "Der", "corrected": "Das", "category": "case",
                           "explanation": "Neuter nominative.", "severity": "error" }] }
            """
        let decoded = try decoder.decode(CorrectResponse.self, from: Data(json.utf8))
        #expect(decoded.correctedBlocks == ["Das ist gut"])
        #expect(decoded.errors.count == 1)
        #expect(decoded.errors[0].category == .grammaticalCase)
        #expect(decoded.errors[0].severity == .error)
        #expect(decoded.errors[0].explanation == "Neuter nominative.")
    }

    @Test("a multi-word category decodes")
    func multiWordCategory() throws {
        let json = """
            { "corrected_blocks": [],
              "errors": [{ "original": "a", "corrected": "b", "category": "word order",
                           "explanation": "x", "severity": "suggestion" }] }
            """
        let decoded = try decoder.decode(CorrectResponse.self, from: Data(json.utf8))
        #expect(decoded.errors[0].category == .wordOrder)
    }

    @Test("every category in the taxonomy decodes from its wire spelling")
    func everyCategoryDecodes() throws {
        for category in ErrorCategory.allCases {
            let json = """
                { "corrected_blocks": [],
                  "errors": [{ "original": "a", "corrected": "b", "category": "\(category.rawValue)",
                               "explanation": "x", "severity": "error" }] }
                """
            let decoded = try decoder.decode(CorrectResponse.self, from: Data(json.utf8))
            #expect(decoded.errors[0].category == category)
        }
    }

    /// Measured 2026-09-30: one reply in three from the default model named
    /// two categories for one item, copying the schema's own "a|b" notation,
    /// and padded the list with empty items. One malformed item cost the
    /// whole correction. The items are decoded leniently; the corrected text
    /// is not.
    @Test("a compound category takes its first valid part")
    func compoundCategory() throws {
        let json = """
            { "corrected_blocks": ["x"],
              "errors": [{ "original": "a", "corrected": "b", "category": "word order|spelling",
                           "explanation": "x", "severity": "error" }] }
            """
        let decoded = try decoder.decode(CorrectResponse.self, from: Data(json.utf8))
        #expect(decoded.errors[0].category == .wordOrder)
    }

    @Test("an unknown category is other; case and spacing do not matter", arguments: [
        ("verb conjugation", ErrorCategory.other),
        ("", ErrorCategory.other),
        (" Spelling ", ErrorCategory.spelling),
        ("tense / spelling", ErrorCategory.spelling),
    ])
    func lenientCategory(_ wire: String, _ expected: ErrorCategory) throws {
        let json = """
            { "corrected_blocks": ["x"],
              "errors": [{ "original": "a", "corrected": "b", "category": "\(wire)",
                           "explanation": "x", "severity": "error" }] }
            """
        let decoded = try decoder.decode(CorrectResponse.self, from: Data(json.utf8))
        #expect(decoded.errors[0].category == expected)
    }

    @Test("an unknown or empty severity counts as an error")
    func lenientSeverity() throws {
        for wire in ["", "major", "Error"] {
            let json = """
                { "corrected_blocks": ["x"],
                  "errors": [{ "original": "a", "corrected": "b", "category": "spelling",
                               "explanation": "x", "severity": "\(wire)" }] }
                """
            let decoded = try decoder.decode(CorrectResponse.self, from: Data(json.utf8))
            #expect(decoded.errors[0].severity == .error)
        }
        let suggestion = """
            { "corrected_blocks": ["x"],
              "errors": [{ "original": "a", "corrected": "b", "category": "spelling",
                           "explanation": "x", "severity": " Suggestion" }] }
            """
        #expect(try decoder.decode(CorrectResponse.self, from: Data(suggestion.utf8))
            .errors[0].severity == .suggestion)
    }

    @Test("empty padding items are dropped")
    func paddingDropped() throws {
        let json = """
            { "corrected_blocks": ["x"],
              "errors": [
                { "original": "a", "corrected": "b", "category": "spelling",
                  "explanation": "x", "severity": "error" },
                { "original": "", "corrected": "", "category": "",
                  "explanation": "", "severity": "" },
                { "original": " ", "corrected": "", "category": "",
                  "explanation": "", "severity": "" } ] }
            """
        let decoded = try decoder.decode(CorrectResponse.self, from: Data(json.utf8))
        #expect(decoded.errors.count == 1)
    }

    @Test("an item correcting a fragment into itself is dropped")
    func noChangeDropped() throws {
        let json = """
            { "corrected_blocks": ["ausser wenn"],
              "errors": [
                { "original": "ausser", "corrected": "ausser", "category": "spelling",
                  "explanation": "spelled with two s", "severity": "error" },
                { "original": "wenn", "corrected": "wenn", "category": "style",
                  "explanation": "x", "severity": "suggestion" } ] }
            """
        #expect(try decoder.decode(CorrectResponse.self, from: Data(json.utf8)).errors.isEmpty)
    }

    @Test("an item fixing only a space at its edge is kept")
    func edgeSpaceFixKept() throws {
        let json = """
            { "corrected_blocks": ["Hallo, Welt"],
              "errors": [{ "original": " ,", "corrected": ",", "category": "spelling",
                           "explanation": "no space before a comma", "severity": "error" }] }
            """
        #expect(try decoder.decode(CorrectResponse.self, from: Data(json.utf8)).errors.count == 1)
    }

    @Test("an item inserting a word is not padding")
    func insertionKept() throws {
        let json = """
            { "corrected_blocks": ["x"],
              "errors": [{ "original": "", "corrected": "dass", "category": "other",
                           "explanation": "a conjunction is missing", "severity": "error" }] }
            """
        #expect(try decoder.decode(CorrectResponse.self, from: Data(json.utf8)).errors.count == 1)
    }

    @Test("an item deleting a word is not padding")
    func deletionKept() throws {
        let json = """
            { "corrected_blocks": ["x"],
              "errors": [{ "original": "ich ", "corrected": "", "category": "word order",
                           "explanation": "drop the repeated subject", "severity": "error" }] }
            """
        #expect(try decoder.decode(CorrectResponse.self, from: Data(json.utf8)).errors.count == 1)
    }

    @Test("corrected blocks are still read strictly")
    func correctedBlocksStrict() {
        #expect(throws: (any Error).self) {
            try decoder.decode(CorrectResponse.self, from: Data(#"{"corrected_blocks": "x", "errors": []}"#.utf8))
        }
    }

    @Test("the explain example from the spec decodes")
    func explainExample() throws {
        let json = """
            { "summary": "It is about a meeting.",
              "notes": [{ "phrase": "auf Anhieb", "explanation": "straight away" }] }
            """
        let decoded = try decoder.decode(ExplainResponse.self, from: Data(json.utf8))
        #expect(decoded.summary == "It is about a meeting.")
        #expect(decoded.notes[0].phrase == "auf Anhieb")
    }
}
