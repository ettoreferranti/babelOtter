import Foundation
import Testing

@testable import BabelOtterKit

@Suite("My language and per-language correction notes (#81)")
struct MyLanguageTests {

    private func decode(_ json: String) throws -> Configuration {
        try JSONDecoder().decode(Configuration.self, from: Data(json.utf8))
    }

    private func encoded(_ configuration: Configuration) throws -> String {
        String(decoding: try JSONEncoder().encode(configuration), as: UTF8.self)
    }

    @Test("a file without myLanguage means English, and stays without it")
    func absentMeansEnglish() throws {
        let configuration = try decode(try encoded(.default))
        #expect(configuration.myLanguage == nil)
        #expect(configuration.myLanguageCode == LanguageCode("en"))
        #expect(configuration.mine == .english)
        #expect(configuration.myLanguageProblem == nil)
        #expect(!(try encoded(configuration)).contains("myLanguage"))
    }

    @Test("a chosen language round-trips and is the one used")
    func chosen() throws {
        var configuration = Configuration.default
        configuration.languages[3].enabled = true
        configuration.myLanguage = LanguageCode("IT")
        let decoded = try decode(try encoded(configuration))
        #expect(decoded.myLanguageCode == LanguageCode("it"))
        #expect(decoded.mine.code == LanguageCode("it"))
        #expect(decoded.myLanguageProblem == nil)
    }

    @Test("not named and English off: the first enabled language, and no problem (review finding)")
    func absentWithEnglishOff() throws {
        var configuration = Configuration.default
        configuration.languages[0].enabled = false
        configuration.languages[2].enabled = true
        #expect(configuration.myLanguage == nil)
        #expect(configuration.myLanguageCode == LanguageCode("de-ch"))
        #expect(configuration.myLanguageProblem == nil)

        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ConfigurationStore(directory: folder)
        try store.save(configuration)
        let loaded = store.load()
        #expect(loaded.problems.isEmpty)
        #expect(loaded.configuration == configuration)
    }

    @Test("a named base code finds the configured regional language")
    func baseCodeNamed() {
        var configuration = Configuration.default
        configuration.myLanguage = LanguageCode("de")
        #expect(configuration.myLanguageCode == LanguageCode("de-ch"))
        #expect(configuration.mine == .swissGerman)
        #expect(configuration.myLanguageProblem == nil)
    }

    @Test("a language not configured, or switched off, is a problem naming why")
    func problems() {
        var configuration = Configuration.default
        configuration.myLanguage = LanguageCode("nl")
        #expect(configuration.myLanguageProblem == "nl is not a configured language")
        #expect(configuration.mine == .english)
        configuration.myLanguage = LanguageCode("fr")
        #expect(configuration.myLanguageProblem == "French is switched off")
    }

    @Test("the store reports an unusable myLanguage as a problem with that field")
    func storeReportsProblem() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ConfigurationStore(directory: folder)
        var configuration = Configuration.default
        configuration.myLanguage = LanguageCode("fr")
        try store.save(configuration)
        let loaded = store.load()
        #expect(loaded.problems.map(\.field) == ["myLanguage"])
        #expect(loaded.configuration == .default)
        configuration.languages[2].enabled = true
        try store.save(configuration)
        #expect(store.load().problems.isEmpty)
    }

    @Test("German, French and Italian ship correction notes; English none")
    func shippedNotes() {
        #expect(LanguageConfig.english.correctionNotes == nil)
        #expect(LanguageConfig.swissGerman.correctionNotes?.contains("mit dem Lehrer") == true)
        #expect(LanguageConfig.french.correctionNotes?.contains("participle") == true)
        #expect(LanguageConfig.italian.correctionNotes?.contains("nella") == true)
    }

    @Test("German's example explanations never fix a person's gender")
    func noPersonGenderExample() {
        // "Leiterin refers to Anna, a woman" made Mistral change "Herr" to
        // "Frau" in a clean letter: an example reads as something to look for.
        let notes = LanguageConfig.swissGerman.correctionNotes ?? ""
        #expect(!notes.contains("woman"))
        #expect(notes.contains("Haus is neuter, so der becomes das"))
    }

    @Test("absent notes take the shipped ones by code or base code; null is none; own notes are kept")
    func notesDecoding() throws {
        func language(_ json: String) throws -> LanguageConfig {
            try JSONDecoder().decode(LanguageConfig.self, from: Data(json.utf8))
        }
        let absent = #"{"code": "fr-CH", "displayName": "F", "localeRules": [], "enabled": true}"#
        #expect(try language(absent).correctionNotes == LanguageConfig.french.correctionNotes)
        let none = #"{"code": "fr", "displayName": "F", "localeRules": [], "enabled": true, "correctionNotes": null}"#
        #expect(try language(none).correctionNotes == nil)
        let own = #"{"code": "it", "displayName": "I", "localeRules": [], "enabled": true, "correctionNotes": "Mine."}"#
        #expect(try language(own).correctionNotes == "Mine.")
        let unknown = #"{"code": "nl", "displayName": "N", "localeRules": [], "enabled": true}"#
        #expect(try language(unknown).correctionNotes == nil)
    }

    @Test("shipped notes are not written to the file; changed or removed ones are")
    func notesEncoding() throws {
        func json(_ language: LanguageConfig) throws -> String {
            String(decoding: try JSONEncoder().encode(language), as: UTF8.self)
        }
        #expect(!(try json(.french)).contains("correctionNotes"))
        #expect(!(try json(.english)).contains("correctionNotes"))
        let own = LanguageConfig(
            code: LanguageCode("fr"), displayName: "French", localeRules: [], enabled: true,
            correctionNotes: "Mine.")
        #expect(try json(own).contains(#""correctionNotes":"Mine.""#))
        let removed = LanguageConfig(
            code: LanguageCode("de-CH"), displayName: "German", localeRules: [], enabled: true)
        #expect(try json(removed).contains(#""correctionNotes":null"#))
        for language in [own, removed, LanguageConfig.french] {
            let back = try JSONDecoder().decode(LanguageConfig.self, from: Data(try json(language).utf8))
            #expect(back == language)
        }
    }

    @Test("the editor sets an enabled language as mine and refuses the rest")
    func editorSetsMine() throws {
        var editor = SettingsEditor(configuration: .default)
        try editor.setMyLanguage(LanguageCode("de-CH"))
        #expect(editor.configuration.myLanguageCode == LanguageCode("de-ch"))
        #expect(throws: SettingsRefusal.languageOff("French")) { try editor.setMyLanguage(LanguageCode("fr")) }
        #expect(throws: SettingsRefusal.unknownLanguage(LanguageCode("nl"))) {
            try editor.setMyLanguage(LanguageCode("nl"))
        }
        #expect(SettingsRefusal.languageOff("French").message == "Switch French on first.")
    }

    @Test("my language cannot be switched off; another can")
    func editorKeepsMineOn() throws {
        var editor = SettingsEditor(configuration: .default)
        try editor.setLanguage(LanguageCode("fr"), enabled: true)
        #expect(throws: SettingsRefusal.isMyLanguage("English")) {
            try editor.setLanguage(LanguageCode("en"), enabled: false)
        }
        try editor.setLanguage(LanguageCode("de-CH"), enabled: false)
        #expect(editor.configuration.enabledLanguages.map(\.code) == [LanguageCode("en"), LanguageCode("fr")])
        #expect(SettingsRefusal.isMyLanguage("English").message == "English is your language; choose another first.")
    }
}
