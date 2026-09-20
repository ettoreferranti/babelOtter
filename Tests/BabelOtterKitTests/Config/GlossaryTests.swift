import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Glossary entries are filtered by language pair")
struct GlossaryTests {

    private let enToDe = LanguagePair(source: LanguageCode("en"), target: LanguageCode("de-ch"))
    private let deToEn = LanguagePair(source: LanguageCode("de-ch"), target: LanguageCode("en"))

    private var glossary: Glossary {
        Glossary(entries: [
            GlossaryEntry(source: "module", target: "Modul", pair: enToDe),
            GlossaryEntry(source: "lecture", target: "Vorlesung", pair: enToDe),
            GlossaryEntry(source: "Modul", target: "module", pair: deToEn),
        ])
    }

    @Test("only entries for the active pair are returned")
    func filtersByPair() {
        #expect(glossary.entries(for: enToDe).map(\.target) == ["Modul", "Vorlesung"])
    }

    @Test("the reverse direction is a different pair")
    func directionMatters() {
        #expect(glossary.entries(for: deToEn).map(\.target) == ["module"])
    }

    @Test("a pair with no entries returns nothing rather than everything")
    func unknownPairIsEmpty() {
        let french = LanguagePair(source: LanguageCode("fr"), target: LanguageCode("en"))
        #expect(glossary.entries(for: french).isEmpty)
    }

    @Test("an empty glossary returns nothing")
    func emptyGlossary() {
        #expect(Glossary(entries: []).entries(for: enToDe).isEmpty)
    }

    @Test("pair codes are normalised, so a hand-edited capital does not hide an entry")
    func pairNormalises() {
        let shouty = LanguagePair(source: LanguageCode("EN"), target: LanguageCode("DE-CH"))
        #expect(glossary.entries(for: shouty).count == 2)
    }

    @Test("a glossary round-trips through Codable")
    func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(glossary)
        #expect(try JSONDecoder().decode(Glossary.self, from: data) == glossary)
    }
}
