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

    @Test("the old entries format loads, one concept each")
    func oldFormat() throws {
        let glossary = try decode(#"""
            {"entries": [
              {"source": "module", "target": "Modul", "pair": {"source": "en", "target": "de-CH"}},
              {"source": "Modul", "target": "course unit", "pair": {"source": "de-CH", "target": "en"}}
            ]}
            """#)
        #expect(glossary.concepts == [
            GlossaryConcept(terms: [en: "module", de: "Modul"]),
            GlossaryConcept(terms: [de: "Modul", en: "course unit"]),
        ])
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
