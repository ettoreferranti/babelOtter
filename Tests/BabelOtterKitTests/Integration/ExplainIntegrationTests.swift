import Foundation
import Testing

@testable import BabelOtterKit

/// The prompt and the configured model must give a usable explanation (#65).
/// Local only, like every test that talks to Ollama:
///
///     BABELOTTER_INTEGRATION=1 swift test --filter ExplainIntegrationTests
///
/// The model is not deterministic, so the idiom case runs three times and
/// must name an idiom at least twice. All texts are synthetic.
@Suite(
    "Integration: the model explains German in English",
    .enabled(if: IntegrationGate.isEnabled), .timeLimit(.minutes(10)))
struct ExplainIntegrationTests {

    private let runs = 3

    private func explain(_ text: String) async throws -> ExplanationResult? {
        let client = OllamaClient(endpoint: .loopback, transport: URLSessionTransport(timeout: 120))
        let explainer = Explainer(configuration: .default, chat: client)
        var finished: ExplanationResult?
        for try await event in explainer.explain(UserText(text)) {
            if case .finished(let result) = event { finished = result }
        }
        return finished
    }

    @Test("idioms get notes of their own")
    func idioms() async throws {
        var hits = 0
        for _ in 0..<runs {
            let result = try #require(try await explain(
                "Das ist nicht mein Bier, aber wir haben den Vertrag unter Dach und Fach gebracht."))
            #expect(!result.summary.isEmpty)
            let phrases = result.notes.map(\.phrase).joined(separator: " | ")
            if phrases.contains("Bier") { hits += 1 } else if phrases.contains("Dach und Fach") { hits += 1 }
        }
        #expect(hits >= 2, "an idiom was named in \(hits) of \(runs) runs")
    }

    @Test("a plain sentence is explained, and the reply parses")
    func plainSentence() async throws {
        let result = try #require(try await explain("Die Sitzung beginnt morgen um 10 Uhr im Hauptgeb\u{00E4}ude."))
        #expect(!result.summary.isEmpty)
    }

    @Test("English is refused before any request")
    func english() async {
        await #expect(throws: ExplanationFailure.notGerman) {
            _ = try await explain("The meeting starts tomorrow at ten o'clock in the main building.")
        }
    }
}
