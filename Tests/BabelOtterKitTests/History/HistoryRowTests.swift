import Foundation
import Testing

@testable import BabelOtterKit

@Suite("A history record's labels in the window")
struct HistoryRowTests {

    private let configuration = Configuration.default

    @Test("a translation shows both languages, with an arrow")
    func translation() {
        let row = HistoryRow(.sample(), configuration: configuration)
        #expect(row.title == "Translate")
        #expect(row.languages == "Swiss Standard German \u{2192} English")
        #expect(row.audience == "Colleagues")
        #expect(row.application == "Mail")
    }

    @Test("Correct and Re-pitch show one language")
    func oneLanguage() {
        for action in [Action.correct, .repitch] {
            let row = HistoryRow(
                .sample(action: action, targetLanguage: nil, profileID: "students"),
                configuration: configuration)
            #expect(row.title == action.displayName)
            #expect(row.languages == "Swiss Standard German")
            #expect(row.audience == "Students")
        }
    }

    @Test("Explain has no audience")
    func explain() {
        let row = HistoryRow(.sample(action: .explain, profileID: nil), configuration: configuration)
        #expect(row.title == "Explain")
        #expect(row.audience == nil)
    }

    @Test("a removed audience or language shows its id")
    func removed() {
        let row = HistoryRow(
            .sample(sourceLanguage: LanguageCode("nl"), targetLanguage: LanguageCode("pt"),
                    profileID: "gone"),
            configuration: configuration)
        #expect(row.languages == "nl \u{2192} pt")
        #expect(row.audience == "gone")
    }

    @Test("the app falls back to its bundle id, else none")
    func application() {
        #expect(HistoryRow(.sample(bundleID: "com.x", appName: nil), configuration: configuration)
            .application == "com.x")
        #expect(HistoryRow(.sample(bundleID: nil, appName: nil), configuration: configuration)
            .application == nil)
    }

    @Test("the excerpt is the first line with text, trimmed")
    func excerptLine() {
        let row = HistoryRow(.sample(source: "\n  \n  Hallo zusammen  \nZeile 2"), configuration: configuration)
        #expect(row.excerpt == "Hallo zusammen")
        #expect(HistoryRow(.sample(source: " \n "), configuration: configuration).excerpt == "")
    }

    @Test("a long first line is cut at 80 characters")
    func excerptCut() {
        let exact = String(repeating: "a", count: 80)
        #expect(HistoryRow(.sample(source: exact), configuration: configuration).excerpt == exact)
        let long = String(repeating: "b", count: 81)
        #expect(HistoryRow(.sample(source: long), configuration: configuration).excerpt
            == String(repeating: "b", count: 80) + "...")
        #expect(HistoryRow.excerptLength == 80)
    }
}
