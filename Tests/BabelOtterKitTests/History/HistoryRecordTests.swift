import Foundation
import Testing

@testable import BabelOtterKit

@Suite("A finished result becomes one history record")
struct HistoryRecordTests {

    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    private let mail = SourceApplication(
        processIdentifier: 42, bundleIdentifier: "com.apple.mail", name: "Mail")
    private let de = LanguageCode("de-CH")
    private let en = LanguageCode("en")

    private func translation(_ direction: Direction, _ text: String) -> TranslationResult {
        TranslationResult(
            text: UserText(text), direction: direction, warnings: ["w"],
            audience: .students, audienceInferred: true)
    }

    @Test("a translation keeps both languages, the audience and the translated text")
    func translationRecord() {
        let record = HistoryRecord(
            translation: translation(Direction(source: de, target: en), "Hello"),
            source: UserText("Hallo"), model: "m", application: mail, date: date)
        #expect(record == HistoryRecord(
            id: nil, date: date, action: .translate, sourceLanguage: de, targetLanguage: en,
            profileID: AudienceProfile.students.id, model: "m",
            sourceBundleID: "com.apple.mail", sourceAppName: "Mail",
            source: UserText("Hallo"), result: UserText("Hello")))
    }

    @Test("a re-pitch keeps its one language and no target")
    func repitchRecord() {
        let record = HistoryRecord(
            repitch: translation(Direction(source: de, target: de), "Guten Tag"),
            source: UserText("Hoi"), model: "m", application: mail, date: date)
        #expect(record.action == .repitch)
        #expect(record.sourceLanguage == de)
        #expect(record.targetLanguage == nil)
        #expect(record.profileID == AudienceProfile.students.id)
        #expect(record.source == UserText("Hoi"))
        #expect(record.result == UserText("Guten Tag"))
    }

    @Test("a correction keeps the original and the corrected text")
    func correctionRecord() {
        let result = CorrectionResult(
            original: UserText("Ich gehe morgen nach hause."),
            corrected: UserText("Ich gehe morgen nach Hause."),
            errors: [], suggestions: [], diff: [], warnings: [], hasNoErrors: false)
        let record = HistoryRecord(
            correction: result, language: de, profileID: "colleagues", model: "m",
            application: mail, date: date)
        #expect(record.action == .correct)
        #expect(record.sourceLanguage == de)
        #expect(record.targetLanguage == nil)
        #expect(record.profileID == "colleagues")
        #expect(record.source == UserText("Ich gehe morgen nach hause."))
        #expect(record.result == UserText("Ich gehe morgen nach Hause."))
        #expect(record.wordCount == 5)
        #expect(record.mistakes.isEmpty)
    }

    @Test("a correction keeps its errors as mistakes, never its suggestions (#78)")
    func correctionMistakes() {
        let error = CorrectionError(
            original: "nach hause", corrected: "nach Hause", category: .spelling,
            explanation: "Hause is a noun", severity: .error)
        let suggestion = CorrectionError(
            original: "gehe", corrected: "fahre", category: .register,
            explanation: "more precise", severity: .suggestion)
        let result = CorrectionResult(
            original: UserText("Ich gehe morgen nach hause."),
            corrected: UserText("Ich gehe morgen nach Hause."),
            errors: [error], suggestions: [suggestion], diff: [], warnings: [], hasNoErrors: false)
        let record = HistoryRecord(
            correction: result, language: de, profileID: "colleagues", model: "m",
            application: mail, date: date)
        #expect(record.mistakes == [Mistake(error)])
        #expect(record.mistakes.first?.original == UserText("nach hause"))
        #expect(record.mistakes.first?.corrected == UserText("nach Hause"))
        #expect(record.mistakes.first?.explanation == UserText("Hause is a noun"))
        #expect(record.mistakes.first?.category == .spelling)
    }

    @Test("other actions keep no word count and no mistakes")
    func noMistakesElsewhere() {
        let record = HistoryRecord.sample()
        #expect(record.wordCount == nil)
        #expect(record.mistakes.isEmpty)
    }

    @Test("an explanation reads German into English, has no audience, and keeps what Copy writes")
    func explanationRecord() {
        let result = ExplanationResult(
            summary: "The meeting moves.",
            notes: [ExplainNote(phrase: "verschoben", explanation: "postponed")],
            warnings: [])
        let record = HistoryRecord(
            explanation: result, source: UserText("Die Sitzung wird verschoben."),
            language: de, explainedIn: en, model: "m", application: mail, date: date)
        #expect(record.action == .explain)
        #expect(record.sourceLanguage == de)
        #expect(record.targetLanguage == en)
        #expect(record.profileID == nil)
        #expect(record.result == UserText(result.copyText))
        #expect(record.result.value.contains("postponed"))
    }

    @Test("an unknown application leaves both application fields empty")
    func noApplication() {
        let record = HistoryRecord(
            translation: translation(Direction(source: de, target: en), "Hello"),
            source: UserText("Hallo"), model: "m", application: nil, date: date)
        #expect(record.sourceBundleID == nil)
        #expect(record.sourceAppName == nil)
    }

    @Test("an application without a bundle id keeps its name")
    func nameOnly() {
        let record = HistoryRecord(
            translation: translation(Direction(source: de, target: en), "Hello"),
            source: UserText("Hallo"), model: "m",
            application: SourceApplication(processIdentifier: 1, bundleIdentifier: nil, name: "Tool"),
            date: date)
        #expect(record.sourceBundleID == nil)
        #expect(record.sourceAppName == "Tool")
    }

    @Test("describing a record never shows its text")
    func redacted() {
        let record = HistoryRecord.sample(source: "Geheimer Entwurf", result: "Secret draft")
        let shown = String(describing: record) + String(reflecting: record)
        #expect(!shown.contains("Geheimer"))
        #expect(!shown.contains("Secret"))
    }
}
