import Foundation
import Testing

@testable import BabelOtterKit

private let en = LanguageCode("en")
private let de = LanguageCode("de-ch")

@Suite("The Glossary tab's edits are checked before they change anything")
struct SettingsGlossaryTests {

    private func editor(_ concepts: [GlossaryConcept] = [], dnt: [String] = []) -> SettingsEditor {
        var configuration = Configuration.default
        configuration.glossary = Glossary(concepts: concepts)
        configuration.doNotTranslate = dnt
        return SettingsEditor(configuration: configuration)
    }

    private func concepts(_ editor: SettingsEditor) -> [[LanguageCode: String]] {
        editor.configuration.glossary.concepts.map(\.terms)
    }

    @Test("a term at the end appends a row; an empty one there stores nothing")
    func append() throws {
        var editor = editor()
        try editor.setTerm("  ", for: en, inConcept: 0)
        #expect(concepts(editor).isEmpty)
        try editor.setTerm(" module ", for: en, inConcept: 0)
        try editor.setTerm("Modul", for: de, inConcept: 0)
        #expect(concepts(editor) == [[en: "module", de: "Modul"]])
        try expectRoundTrip(editor)
    }

    @Test("clearing a term removes its language; clearing the last removes the row")
    func clear() throws {
        var editor = editor([GlossaryConcept(terms: [en: "module", de: "Modul"]), GlossaryConcept(terms: [en: "x"])])
        try editor.setTerm("", for: de, inConcept: 0)
        #expect(concepts(editor) == [[en: "module"], [en: "x"]])
        try editor.setTerm(" ", for: en, inConcept: 0)
        #expect(concepts(editor) == [[en: "x"]])
        try expectRoundTrip(editor)
    }

    @Test("a term already in another row for that language is refused, ignoring case")
    func duplicate() throws {
        var editor = editor([GlossaryConcept(terms: [en: "module", de: "Modul"])])
        let before = editor
        expectRefusal(.termInUse("MODUL", "Swiss Standard German")) {
            try editor.setTerm("MODUL", for: de, inConcept: 1)
        }
        #expect(editor == before)
        // Its own row, and another language, are free.
        try editor.setTerm("modul", for: de, inConcept: 0)
        try editor.setTerm("Modul", for: en, inConcept: 1)
        #expect(concepts(editor) == [[en: "module", de: "modul"], [en: "Modul"]])
        #expect(SettingsRefusal.termInUse("Modul", "Swiss Standard German").message
            == "Modul is already in another row for Swiss Standard German.")
    }

    @Test("a language that is not configured is named by its code, and kept through edits")
    func hiddenLanguage() throws {
        let latin = LanguageCode("la")
        var editor = editor([GlossaryConcept(terms: [latin: "modulus", en: "module"])])
        expectRefusal(.termInUse("modulus", "la")) { try editor.setTerm("modulus", for: latin, inConcept: 1) }
        try editor.setTerm("Modul", for: de, inConcept: 0)
        try editor.setTerm("", for: en, inConcept: 0)
        #expect(concepts(editor) == [[latin: "modulus", de: "Modul"]])
    }

    @Test("terms have at most 80 characters, and the glossary at most 200 rows")
    func limits() throws {
        var editor = editor()
        try editor.setTerm(String(repeating: "a", count: 80), for: en, inConcept: 0)
        expectRefusal(.termTooLong) { try editor.setTerm(String(repeating: "a", count: 81), for: de, inConcept: 0) }
        var full = self.editor((0..<200).map { GlossaryConcept(terms: [en: "t\($0)"]) })
        expectRefusal(.tooManyRows) { try full.setTerm("one more", for: en, inConcept: 200) }
        // A row that exists can still be edited at the limit.
        try full.setTerm("Modul", for: de, inConcept: 199)
        #expect(SettingsRefusal.tooManyRows.message == "At most 200 rows.")
        #expect(SettingsRefusal.termTooLong.message == "At most 80 characters.")
    }

    @Test("an index past the end is refused, as are deletions of missing rows")
    func indexes() throws {
        var editor = editor([GlossaryConcept(terms: [en: "a"]), GlossaryConcept(terms: [en: "b"]), GlossaryConcept(terms: [en: "c"])])
        expectRefusal(.noSuchRow) { try editor.setTerm("x", for: en, inConcept: 4) }
        expectRefusal(.noSuchRow) { try editor.setTerm("x", for: en, inConcept: -1) }
        expectRefusal(.noSuchRow) { try editor.deleteConcepts(at: [1, 3]) }
        #expect(concepts(editor).count == 3)
        try editor.deleteConcepts(at: [0, 2])
        #expect(concepts(editor) == [[en: "b"]])
        try expectRoundTrip(editor)
        #expect(SettingsRefusal.noSuchRow.message == "That row is no longer there.")
    }

    @Test("do-not-translate terms are trimmed, exact duplicates refused, other cases allowed")
    func doNotTranslate() throws {
        var editor = editor(dnt: ["NORDA"])
        try editor.addDoNotTranslate("  GitHub ")
        try editor.addDoNotTranslate("Norda")
        #expect(editor.configuration.doNotTranslate == ["NORDA", "GitHub", "Norda"])
        expectRefusal(.dntInUse("NORDA")) { try editor.addDoNotTranslate("NORDA") }
        expectRefusal(.emptyTerm) { try editor.addDoNotTranslate(" ") }
        expectRefusal(.termTooLong) { try editor.addDoNotTranslate(String(repeating: "x", count: 81)) }
        try editor.setDoNotTranslate("GitLab", at: 1)
        try editor.setDoNotTranslate("GitLab", at: 1)
        expectRefusal(.dntInUse("NORDA")) { try editor.setDoNotTranslate("NORDA", at: 2) }
        try editor.setDoNotTranslate(" ", at: 2)
        #expect(editor.configuration.doNotTranslate == ["NORDA", "GitLab"])
        expectRefusal(.noSuchRow) { try editor.setDoNotTranslate("x", at: 2) }
        expectRefusal(.noSuchRow) { try editor.setDoNotTranslate("x", at: -1) }
        try editor.deleteDoNotTranslate(at: [0])
        expectRefusal(.noSuchRow) { try editor.deleteDoNotTranslate(at: [1]) }
        #expect(editor.configuration.doNotTranslate == ["GitLab"])
        try expectRoundTrip(editor)
        #expect(SettingsRefusal.dntInUse("X").message == "X is already in the list.")
        #expect(SettingsRefusal.emptyTerm.message == "Enter a term.")
    }

    @Test("the list holds at most 100 terms")
    func doNotTranslateLimit() throws {
        var editor = editor(dnt: (0..<99).map { "t\($0)" })
        try editor.addDoNotTranslate("last")
        expectRefusal(.tooManyTerms) { try editor.addDoNotTranslate("one more") }
        #expect(editor.configuration.doNotTranslate.count == 100)
        #expect(SettingsRefusal.tooManyTerms.message == "At most 100 terms.")
    }
}
