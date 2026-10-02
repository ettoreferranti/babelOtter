import Foundation
import Testing

@testable import BabelOtterKit

private func load(_ correction: String, _ translation: String = "[]") throws -> GoldenSet {
    try GoldenSet.load(correction: Data(correction.utf8), translation: Data(translation.utf8))
}

/// The error a single bad correction case raises.
private func correctionError(_ caseJSON: String) -> GoldenSetError? {
    do {
        _ = try load("[\(caseJSON)]")
        return nil
    } catch let error as GoldenSetError {
        return error
    } catch {
        return nil
    }
}

private func translationError(_ caseJSON: String) -> GoldenSetError? {
    do {
        _ = try load("[]", "[\(caseJSON)]")
        return nil
    } catch let error as GoldenSetError {
        return error
    } catch {
        return nil
    }
}

@Suite("Eval: the golden set loads and validates")
struct GoldenSetTests {

    @Test("a minimal correction case loads with its defaults")
    func correctionDefaults() throws {
        let set = try load("""
            [{"id": "a", "text": "Ich bin jetz da.",
              "fixes": [{"wrong": "jetz", "right": ["jetzt"], "category": "spelling"}]}]
            """)
        #expect(set.correction == [CorrectionCase(
            id: "a", text: "Ich bin jetz da.", profileID: "colleagues", terms: [],
            fixes: [ExpectedFix(wrong: "jetz", right: ["jetzt"], category: .spelling)],
            mustNot: [], clean: false)])
    }

    @Test("a translation case loads with its defaults and direction")
    func translationDefaults() throws {
        let set = try load("[]", """
            [{"id": "t", "text": "Hello Otterbach.", "direction": "en-de-ch",
              "terms": ["Otterbach"], "reference": "Hallo Otterbach."}]
            """)
        let only = try #require(set.translation.first)
        #expect(only.profileID == "colleagues")
        #expect(only.direction == .englishToSwissGerman)
        #expect(only.direction.direction == Direction(source: LanguageCode("en"), target: LanguageCode("de-CH")))
        #expect(only.direction.targetIsGerman)
        #expect(!TranslationDirection.swissGermanToEnglish.targetIsGerman)
    }

    @Test("a clean case and a guard-only case are valid")
    func cleanAndGuardOnly() throws {
        let set = try load("""
            [{"id": "c", "text": "Alles gut.", "fixes": [], "clean": true},
             {"id": "g", "text": "mit der Kollege", "fixes": [], "mustNot": ["Kollegin"]}]
            """)
        #expect(set.correction.map(\.clean) == [true, false])
    }

    @Test("an invalid correction case names its id and field", arguments: [
        (#"{"id": "", "text": "x", "fixes": [], "clean": true}"#, "id"),
        (#"{"id": "a", "text": "", "fixes": [], "clean": true}"#, "text"),
        (#"{"id": "a", "text": "Hallo.", "profile": "nobody", "fixes": [], "clean": true}"#, "profile"),
        (#"{"id": "a", "text": "Hallo.", "terms": ["Otterbach"], "fixes": [], "clean": true}"#, "terms[0]"),
        (#"{"id": "a", "text": "Ich bin jetzt da.", "fixes": [{"wrong": "jetz", "right": ["jetzt"], "category": "spelling"}]}"#, "fixes[0].wrong"),
        (#"{"id": "a", "text": "Ich bin jetz da.", "fixes": [{"wrong": "jetz", "right": [], "category": "spelling"}]}"#, "fixes[0].right"),
        (#"{"id": "a", "text": "Ich bin jetz da.", "fixes": [{"wrong": "jetz", "right": [""], "category": "spelling"}]}"#, "fixes[0].right[0]"),
        (#"{"id": "a", "text": "Ich bin jetz da.", "fixes": [{"wrong": "bin jetz", "right": ["bin jetz schon"], "category": "spelling"}]}"#, "fixes[0].right[0]"),
        (#"{"id": "a", "text": "Ich bin jetz da.", "fixes": [{"wrong": "jetz", "right": ["jetzt"], "category": "typo"}]}"#, "fixes[0].category"),
        (#"{"id": "a", "text": "Ich bin jetz da.", "fixes": [{"wrong": "jetz", "right": ["jetzt"], "category": "spelling"}], "clean": true}"#, "fixes"),
        (#"{"id": "a", "text": "Ich bin da.", "fixes": []}"#, "fixes"),
        (#"{"id": "a", "text": "mit der Kollegin", "fixes": [], "mustNot": ["Kollegin"]}"#, "mustNot[0]"),
        (#"{"id": "a", "text": "Hallo.", "fixes": [], "mustNot": [""]}"#, "mustNot[0]"),
    ])
    func invalidCorrection(caseJSON: String, field: String) {
        let error = correctionError(caseJSON)
        #expect(error?.field == field)
        #expect(error?.file == "correction.json")
    }

    @Test("an invalid translation case names its id and field", arguments: [
        (#"{"id": "t", "text": "Hi.", "direction": "en-fr", "reference": "Salut."}"#, "direction"),
        (#"{"id": "t", "text": "Hi.", "direction": "en-de-ch", "reference": ""}"#, "reference"),
        (#"{"id": "t", "text": "Hi.", "direction": "en-de-ch", "terms": ["Otterbach"], "reference": "Hallo."}"#, "terms[0]"),
        (#"{"id": "t", "text": "Hi Otterbach.", "direction": "en-de-ch", "terms": ["Otterbach"], "reference": "Hallo."}"#, "terms[0]"),
        (#"{"id": "t", "text": "Hi.", "direction": "en-de-ch", "profile": "nobody", "reference": "Hallo."}"#, "profile"),
    ])
    func invalidTranslation(caseJSON: String, field: String) {
        let error = translationError(caseJSON)
        #expect(error?.field == field)
        #expect(error?.caseID == "t")
        #expect(error?.file == "translation.json")
    }

    @Test("ids are unique across both files")
    func duplicateAcrossFiles() {
        #expect(throws: GoldenSetError.self) {
            try load(
                #"[{"id": "same", "text": "Alles gut.", "fixes": [], "clean": true}]"#,
                #"[{"id": "same", "text": "Hi.", "direction": "en-de-ch", "reference": "Hallo."}]"#)
        }
    }

    @Test("malformed JSON is reported against its file")
    func malformed() {
        let error = correctionError("{")
        #expect(error?.field == "json")
        #expect(error?.caseID == nil)
    }

    @Test("the error reads as one line naming the file, case and field")
    func description() {
        let error = GoldenSetError(
            file: "correction.json", caseID: "a", field: "fixes[0].wrong", reason: "is missing")
        #expect(error.description == #"correction.json: case "a", fixes[0].wrong: is missing"#)
    }
}
