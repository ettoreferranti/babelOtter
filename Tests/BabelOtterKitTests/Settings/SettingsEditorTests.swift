import Foundation
import Testing

@testable import BabelOtterKit

/// Every accepted edit must load back as itself.
func expectRoundTrip(_ editor: SettingsEditor, sourceLocation: SourceLocation = #_sourceLocation) throws {
    let data = try JSONEncoder.configuration.encode(editor.configuration)
    let back = try JSONDecoder().decode(Configuration.self, from: data)
    #expect(back == editor.configuration, sourceLocation: sourceLocation)
}

func expectRefusal(
    _ refusal: SettingsRefusal, _ body: () throws -> Void,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(throws: refusal, sourceLocation: sourceLocation) { try body() }
}

@Suite("The settings window's edits are checked before they change anything")
struct SettingsEditorTests {

    private let french = LanguageConfig(
        code: LanguageCode("fr"), displayName: "French", localeRules: [], enabled: false)

    @Test("a language can be switched while two stay on")
    func languages() throws {
        var editor = SettingsEditor(configuration: .default)
        try editor.setLanguage(LanguageCode("fr"), enabled: true)
        // English is my language until another is chosen (#81).
        try editor.setMyLanguage(LanguageCode("fr"))
        try editor.setLanguage(LanguageCode("en"), enabled: false)
        #expect(editor.configuration.enabledLanguages.map(\.code.rawValue) == ["de-ch", "fr"])
        try expectRoundTrip(editor)
        let before = editor
        // French is now my language, which says so before the count does.
        expectRefusal(.isMyLanguage("French")) { try editor.setLanguage(LanguageCode("fr"), enabled: false) }
        expectRefusal(.tooFewLanguages) { try editor.setLanguage(LanguageCode("de-CH"), enabled: false) }
        #expect(editor == before)
        try editor.setLanguage(LanguageCode("fr"), enabled: true)
        #expect(editor == before)
    }

    @Test("with only two languages on, neither can be switched off")
    func lastTwo() {
        var editor = SettingsEditor(configuration: .default)
        // English is my language (#81): that refusal names the reason that
        // still holds once a third language is on.
        expectRefusal(.isMyLanguage("English")) { try editor.setLanguage(LanguageCode("en"), enabled: false) }
        expectRefusal(.tooFewLanguages) { try editor.setLanguage(LanguageCode("de-CH"), enabled: false) }
        #expect(editor.configuration == .default)
        expectRefusal(.unknownLanguage(LanguageCode("nl"))) {
            try editor.setLanguage(LanguageCode("nl"), enabled: true)
        }
        #expect(SettingsRefusal.tooFewLanguages.message == "At least two languages stay on.")
        #expect(SettingsRefusal.unknownLanguage(LanguageCode("it")).message == "it is not a configured language.")
    }

    @Test("retention takes 1 to 36,500 days, unlimited or off")
    func retention() throws {
        var editor = SettingsEditor(configuration: .default)
        for retention in [HistoryRetention.days(1), .days(36_500), .unlimited, .off, .days(30)] {
            try editor.setRetention(retention)
            #expect(editor.configuration.retentionDays == retention)
            try expectRoundTrip(editor)
        }
        let range = SettingsRefusal.outOfRange("Between 1 and 36,500 days")
        expectRefusal(range) { try editor.setRetention(.days(0)) }
        expectRefusal(range) { try editor.setRetention(.days(36_501)) }
        #expect(editor.configuration.retentionDays == .days(30))
        #expect(range.message == "Between 1 and 36,500 days")
    }

    @Test("the timeout takes 5 to 600 seconds")
    func timeout() throws {
        var editor = SettingsEditor(configuration: .default)
        try editor.setTimeout(seconds: 5)
        try editor.setTimeout(seconds: 600)
        #expect(editor.configuration.timeoutSeconds == 600)
        try expectRoundTrip(editor)
        let range = SettingsRefusal.outOfRange("Between 5 and 600 seconds")
        expectRefusal(range) { try editor.setTimeout(seconds: 4.9) }
        expectRefusal(range) { try editor.setTimeout(seconds: 600.1) }
        expectRefusal(range) { try editor.setTimeout(seconds: .nan) }
        #expect(editor.configuration.timeoutSeconds == 600)
    }

    @Test("the clipboard switch is written as set")
    func strictCapture() throws {
        var editor = SettingsEditor(configuration: .default)
        editor.setStrictCaptureOnly(true)
        #expect(editor.configuration.strictCaptureOnly)
        try expectRoundTrip(editor)
        editor.setStrictCaptureOnly(false)
        #expect(!editor.configuration.strictCaptureOnly)
    }

    @Test("a model is trimmed, and an empty one refused")
    func model() throws {
        var editor = SettingsEditor(configuration: .default)
        try editor.setModel("  qwen3:14b \n", for: .explain)
        #expect(editor.configuration.models[.explain] == "qwen3:14b")
        #expect(editor.configuration.model(for: .translate) == Configuration.defaultModel)
        try expectRoundTrip(editor)
        expectRefusal(.emptyModel) { try editor.setModel(" ", for: .translate) }
        #expect(editor.configuration.models[.translate] == Configuration.defaultModel)
        #expect(SettingsRefusal.emptyModel.message == "Choose a model.")
    }
}
