import Foundation
import Testing

@testable import BabelOtterKit

@Suite("The quiet hint under a translation (#136)")
struct TranslateHintTests {

    private let english = LanguageCode("en")
    private let german = LanguageCode("de-ch")
    private let french = LanguageCode("fr")
    private let today = LearningDay(number: 20_261_111)
    private let yesterday = LearningDay(number: 20_261_110)

    private func hint(
        _ source: LanguageCode, _ target: LanguageCode, words: Int = 12, last: LearningDay? = nil,
        mine: LanguageCode? = nil
    ) -> TranslateHint? {
        TranslateHint.hint(
            for: Direction(source: source, target: target), myLanguage: mine ?? english, words: words,
            lastHintDay: last, today: today)
    }

    @Test("from my language: write it yourself in the target next time")
    func fromMine() {
        #expect(hint(english, german) == .write(german))
        #expect(hint(LanguageCode("en-gb"), french) == .write(french))
    }

    @Test("into my language: try Explain")
    func intoMine() {
        #expect(hint(german, english) == .explain)
        #expect(hint(LanguageCode("de"), english, mine: LanguageCode("en-us")) == .explain)
    }

    @Test("between two languages of which neither, or both, are mine: nothing")
    func neither() {
        #expect(hint(german, french) == nil)
        #expect(hint(english, LanguageCode("en-gb")) == nil)
    }

    @Test("texts under five words get no hint")
    func short() {
        #expect(hint(english, german, words: 4) == nil)
        #expect(hint(english, german, words: 5) == .write(german))
    }

    @Test("at most one hint a day")
    func onceADay() {
        #expect(hint(english, german, last: today) == nil)
        #expect(hint(german, english, last: today) == nil)
        #expect(hint(english, german, last: yesterday) == .write(german))
    }

    @Test("the wording, with the hotkey when there is one")
    func wording() {
        let languages = LanguageConfig.shippedDefaults
        let name = Milestone.name(of: german, in: languages)
        #expect(TranslateHint.write(german).text(languages: languages, hotKey: "control+option+C")
            == "Next time, try writing it in \(name) yourself, then press Correct (control+option+C).")
        #expect(TranslateHint.write(french).text(languages: [], hotKey: nil)
            == "Next time, try writing it in fr yourself, then press Correct.")
        #expect(TranslateHint.explain.text(languages: languages, hotKey: "control+option+E")
            == "Want to see how this text works? Try Explain (control+option+E).")
        #expect(TranslateHint.explain.text(languages: languages, hotKey: nil)
            == "Want to see how this text works? Try Explain.")
    }

    @Test("each hint points to its action")
    func actions() {
        #expect(TranslateHint.write(german).action == .correct)
        #expect(TranslateHint.explain.action == .explain)
    }

    @Test("the hotkey is the file's, the default when unnamed, none when off")
    func hotKeys() {
        #expect(TranslateHint.hotKey(for: .correct, in: nil) == "control+option+C")
        #expect(TranslateHint.hotKey(for: .explain, in: HotKeyBindings()) == "control+option+E")
        #expect(TranslateHint.hotKey(for: .correct, in: HotKeyBindings(correct: .off)) == nil)
        #expect(TranslateHint.hotKey(for: .correct, in: HotKeyBindings(correct: .text("command+shift+K")))
            == "command+shift+K")
        #expect(TranslateHint.hotKey(for: .explain, in: HotKeyBindings(correct: .off)) == "control+option+E")
    }
}
