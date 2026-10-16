import Foundation
import Testing

@testable import BabelOtterKit

/// The prompt and the configured model must re-aim a text without losing
/// its facts (#66). Local only, like every test that talks to Ollama:
///
///     BABELOTTER_INTEGRATION=1 swift test --filter RepitchIntegrationTests
///
/// The model is not deterministic, so each case runs three times and must
/// pass at least twice. All texts are synthetic.
@Suite(
    "Integration: the model re-pitches a text for another audience",
    .enabled(if: IntegrationGate.isEnabled), .timeLimit(.minutes(10)))
struct RepitchIntegrationTests {

    private let runs = 3

    private func repitch(_ text: String, for audience: AudienceProfile) async throws -> String? {
        let client = OllamaClient(endpoint: .loopback, transport: URLSessionTransport(timeout: 120))
        let translator = Translator(configuration: .default, chat: client)
        guard case .success(let language) = translator.language(for: UserText(text)) else { return nil }
        var finished: String?
        for try await event in translator.repitch(UserText(text), language: language, audience: audience) {
            if case .finished(let result) = event { finished = result.text.value }
        }
        return finished
    }

    private func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
    }

    @Test("a du-form message for Administration uses Sie, no eszett, and keeps its facts")
    func germanToAdministration() async throws {
        let draft = "Hallo Thomas, kannst du mir bis Freitag, 14.11.2026, die Unterlagen schicken? "
            + "Wir treffen uns um 14:30 im Raum B 2.13. Danke dir!"
        var passes = 0
        for _ in 0..<runs {
            let result = try #require(try await repitch(draft, for: .administration))
            let found = words(result)
            var ok = found.contains("sie")
            for informal in ["du", "dich", "dir", "dein", "deine"] where found.contains(informal) { ok = false }
            if result.contains("\u{00DF}") { ok = false }
            if !FactCheck.missing(from: draft, in: result).isEmpty { ok = false }
            if ok { passes += 1 } else { print("re-pitch failed checks: \(result)") }
        }
        #expect(passes >= 2, "passed \(passes) of \(runs)")
    }

    @Test("an English note for Students stays English and keeps its facts")
    func englishToStudents() async throws {
        let draft = "Hi Tom, quick reminder: the review moves to 18 November 2026 at 10:15 "
            + "in room 4.07. Can you bring the slides?"
        let detector = LanguageDetector(configuration: .default)
        var passes = 0
        for _ in 0..<runs {
            let result = try #require(try await repitch(draft, for: .students))
            var ok = detector.detect(result).languageCode?.baseSubtag == LanguageCode("en")
            if !FactCheck.missing(from: draft, in: result).isEmpty { ok = false }
            if ok { passes += 1 } else { print("re-pitch failed checks: \(result)") }
        }
        #expect(passes >= 2, "passed \(passes) of \(runs)")
    }
}
