import Foundation
import Testing

@testable import BabelOtterKit

private let en = LanguageCode("en")
private let de = LanguageCode("de-ch")
private let fr = LanguageCode("fr")

@Suite("A concept glossary gives each direction the rows with both its languages")
struct GlossaryTests {

    private let enToDe = LanguagePair(source: en, target: de)
    private let deToEn = LanguagePair(source: de, target: en)

    private var glossary: Glossary {
        Glossary(concepts: [
            GlossaryConcept(terms: [en: "module", de: "Modul", fr: "module"]),
            GlossaryConcept(terms: [en: "lecture", de: "Vorlesung"]),
            GlossaryConcept(terms: [de: "Studiengang", fr: "fili\u{00E8}re"]),
        ])
    }

    @Test("each direction gets every row with both languages, in order")
    func bothDirections() {
        let forward = glossary.entries(for: enToDe)
        #expect(forward.map(\.source) == ["module", "lecture"])
        #expect(forward.map(\.target) == ["Modul", "Vorlesung"])
        #expect(forward.allSatisfy { $0.pair == enToDe })
        let back = glossary.entries(for: deToEn)
        #expect(back.map(\.source) == ["Modul", "Vorlesung"])
        #expect(back.map(\.target) == ["module", "lecture"])
    }

    @Test("a third language works with no code change")
    func thirdLanguage() {
        let deToFr = glossary.entries(for: LanguagePair(source: de, target: fr))
        #expect(deToFr.map(\.target) == ["module", "fili\u{00E8}re"])
        #expect(glossary.entries(for: LanguagePair(source: en, target: fr)).map(\.source) == ["module"])
    }

    @Test("a pair no row covers returns nothing rather than everything")
    func uncoveredPair() {
        #expect(glossary.entries(for: LanguagePair(source: LanguageCode("it"), target: en)).isEmpty)
        #expect(Glossary().entries(for: enToDe).isEmpty)
    }

    @Test("a source term two rows give, by hand, reaches the prompt once, from the first row")
    func handEditedDuplicate() {
        let glossary = Glossary(concepts: [
            GlossaryConcept(terms: [en: "module", de: "Modul"]),
            GlossaryConcept(terms: [en: "Module", de: "Baustein"]),
        ])
        #expect(glossary.entries(for: enToDe).map(\.target) == ["Modul"])
        #expect(glossary.entries(for: deToEn).map(\.target) == ["module", "Module"])
    }

    @Test("a pair within one language maps each term to itself")
    func sameLanguage() {
        #expect(glossary.entries(for: LanguagePair(source: de, target: de)).map(\.target)
            == ["Modul", "Vorlesung", "Studiengang"])
    }

    @Test("codes are normalised, so a hand-edited capital does not hide a row")
    func normalised() {
        let shouty = LanguagePair(source: LanguageCode("EN"), target: LanguageCode("DE-CH"))
        #expect(glossary.entries(for: shouty).count == 2)
    }

    @Test("terms are trimmed, an empty one removes its language, and empty rows are dropped")
    func trimmed() {
        var concept = GlossaryConcept(terms: [en: "  module ", de: " \n"])
        #expect(concept.terms == [en: "module"])
        concept.set("Modul", for: de)
        concept.set("", for: en)
        #expect(concept.terms == [de: "Modul"])
        concept.set(" ", for: de)
        #expect(concept.isEmpty)
        #expect(Glossary(concepts: [concept, GlossaryConcept(terms: [en: "x"])]).concepts.count == 1)
    }
}

@Suite("The glossary in config.json, new format and old")
struct GlossaryCodingTests {

    private func decode(_ json: String) throws -> Glossary {
        try JSONDecoder().decode(Glossary.self, from: Data(json.utf8))
    }

    @Test("concepts are written as objects by language code, sorted, and read back")
    func roundTrip() throws {
        let glossary = Glossary(concepts: [GlossaryConcept(terms: [en: "module", de: "Modul"])])
        let text = String(decoding: try JSONEncoder.configuration.encode(glossary), as: UTF8.self)
        #expect(text.contains(#""concepts""#))
        #expect(!text.contains(#""entries""#))
        let deRange = try #require(text.range(of: #""de-ch""#))
        let enRange = try #require(text.range(of: #""en""#))
        #expect(deRange.lowerBound < enRange.lowerBound)
        #expect(try decode(text) == glossary)
    }

    @Test("old entries sharing a term merge into one concept; the first rendering wins")
    func oldFormatMerges() throws {
        let glossary = try decode(#"""
            {"entries": [
              {"source": "module", "target": "Modul", "pair": {"source": "en", "target": "de-CH"}},
              {"source": "modul", "target": "course unit", "pair": {"source": "de-CH", "target": "en"}},
              {"source": "Modul", "target": "module", "pair": {"source": "de-ch", "target": "en"}},
              {"source": "lecture", "target": "Vorlesung", "pair": {"source": "en", "target": "de-ch"}},
              {"source": "Modul", "target": "module", "pair": {"source": "de-ch", "target": "fr"}}
            ]}
            """#)
        #expect(glossary.concepts == [
            GlossaryConcept(terms: [en: "module", de: "Modul", fr: "module"]),
            GlossaryConcept(terms: [en: "lecture", de: "Vorlesung"]),
        ])
        // No term reaches the prompt twice, in either direction.
        #expect(glossary.entries(for: LanguagePair(source: de, target: en)).map(\.target) == ["module", "lecture"])
        #expect(glossary.entries(for: LanguagePair(source: en, target: de)).map(\.target) == ["Modul", "Vorlesung"])
    }

    @Test("an old entry within one language is dropped")
    func oldSameLanguage() throws {
        let glossary = try decode(#"""
            {"entries": [{"source": "Studiengang", "target": "Studienprogramm", "pair": {"source": "de-ch", "target": "de-ch"}}]}
            """#)
        #expect(glossary.concepts.isEmpty)
    }

    @Test("two spellings of one language code keep the first in sorted order")
    func caseCollision() throws {
        let glossary = try decode(#"{"concepts": [{"de-ch": "b", "de-CH": "a", "en": "x"}]}"#)
        #expect(glossary.concepts == [GlossaryConcept(terms: [de: "a", en: "x"])])
        let blankFirst = try decode(#"{"concepts": [{"DE-CH": " ", "de-ch": "b"}]}"#)
        #expect(blankFirst.concepts == [GlossaryConcept(terms: [de: "b"])])
    }

    @Test("concepts that are null are a problem, not a fall back to entries")
    func nullConcepts() {
        #expect(throws: DecodingError.self) {
            _ = try decode(#"{"concepts": null, "entries": []}"#)
        }
    }

    @Test("with both formats, concepts win; with neither, the glossary is empty")
    func precedence() throws {
        let both = try decode(#"""
            {"concepts": [{"en": "a", "de-ch": "b"}],
             "entries": [{"source": "x", "target": "y", "pair": {"source": "en", "target": "de-ch"}}]}
            """#)
        #expect(both.concepts == [GlossaryConcept(terms: [en: "a", de: "b"])])
        #expect(try decode("{}").concepts.isEmpty)
    }

    @Test("blank terms and rows are dropped at load; an unknown language is kept")
    func lenient() throws {
        let glossary = try decode(#"{"concepts": [{"en": " ", "de-ch": "Modul", "la": "modulus"}, {"en": ""}]}"#)
        #expect(glossary.concepts == [GlossaryConcept(terms: [de: "Modul", LanguageCode("la"): "modulus"])])
    }

    @Test("a term that is not text is a problem, not a silent default")
    func wrongType() {
        #expect(throws: DecodingError.self) { _ = try decode(#"{"concepts": [{"en": 3}]}"#) }
    }
}
