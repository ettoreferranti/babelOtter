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
                           "explanation_en": "Neuter nominative.", "severity": "error" }] }
            """
        let decoded = try decoder.decode(CorrectResponse.self, from: Data(json.utf8))
        #expect(decoded.correctedBlocks == ["Das ist gut"])
        #expect(decoded.errors.count == 1)
        #expect(decoded.errors[0].category == .grammaticalCase)
        #expect(decoded.errors[0].severity == .error)
        #expect(decoded.errors[0].explanationEn == "Neuter nominative.")
    }

    @Test("a multi-word category decodes")
    func multiWordCategory() throws {
        let json = """
            { "corrected_blocks": [],
              "errors": [{ "original": "a", "corrected": "b", "category": "word order",
                           "explanation_en": "x", "severity": "suggestion" }] }
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
                               "explanation_en": "x", "severity": "error" }] }
                """
            let decoded = try decoder.decode(CorrectResponse.self, from: Data(json.utf8))
            #expect(decoded.errors[0].category == category)
        }
    }

    @Test("the explain example from the spec decodes")
    func explainExample() throws {
        let json = """
            { "summary_en": "It is about a meeting.",
              "notes": [{ "phrase": "auf Anhieb", "explanation_en": "straight away" }] }
            """
        let decoded = try decoder.decode(ExplainResponse.self, from: Data(json.utf8))
        #expect(decoded.summaryEn == "It is about a meeting.")
        #expect(decoded.notes[0].phrase == "auf Anhieb")
    }
}
