import Foundation
import Testing

@testable import BabelOtterKit

/// The prompt and the configured model must agree on who a text is for (#52).
/// Local only, like every test that talks to Ollama:
///
///     BABELOTTER_INTEGRATION=1 swift test --filter AudienceInferenceIntegrationTests
///
/// The model is not deterministic, so each text runs three times and must
/// give the expected answer at least twice. A case that flaps is a finding
/// about the prompt, not noise to retry away. All texts are synthetic.
@Suite(
    "Integration: the model infers who a text is for",
    .enabled(if: IntegrationGate.isEnabled), .timeLimit(.minutes(10)))
struct AudienceInferenceIntegrationTests {

    private let runs = 3

    /// The first `.audience` event; the stream is dropped there, which
    /// cancels the rest of the generation.
    private func reported(
        _ text: String, fallback: AudienceProfile
    ) async throws -> (AudienceProfile, Bool)? {
        let client = OllamaClient(endpoint: .loopback, transport: URLSessionTransport(timeout: 120))
        let translator = Translator(configuration: .default, chat: client)
        let stream = translator.translate(
            UserText(text),
            direction: Direction(source: LanguageConfig.english.code, target: LanguageConfig.swissGerman.code),
            audience: .infer(profiles: AudienceProfile.shippedDefaults, fallback: fallback))
        for try await event in stream {
            if case .audience(let profile, let inferred) = event { return (profile, inferred) }
        }
        return nil
    }

    private func hits(
        _ text: String, _ expected: (AudienceProfile, Bool), fallback: AudienceProfile = .colleagues
    ) async throws -> Int {
        var count = 0
        for _ in 0..<runs {
            let answer = try await reported(text, fallback: fallback)
            if let answer {
                if answer.0 == expected.0 {
                    if answer.1 == expected.1 { count += 1 }
                }
            }
        }
        return count
    }

    @Test("an email to students is for Students")
    func students() async throws {
        let text = """
            Dear students,

            the exam for the module Statistics 1 takes place on 12 January in room TB 610. \
            Please bring your student ID and a calculator. Good luck with your preparation!
            """
        #expect(try await hits(text, (.students, true)) >= 2)
    }

    @Test("a message to a colleague is for Colleagues")
    func colleagues() async throws {
        let text = """
            Hi Anna, I merged the PR for the parser fix and CI is green. \
            Could you rebase your branch on main before the stand-up tomorrow?
            """
        #expect(try await hits(text, (.colleagues, true)) >= 2)
    }

    @Test("a neutral sentence gives no sign, so the fallback")
    func neutral() async throws {
        let text = "The meeting room on the third floor is closed on Friday."
        #expect(try await hits(text, (.colleagues, false)) >= 2)
    }

    /// Measured 2026-10-15 before evidence was required: with Students
    /// remembered, this sentence was guessed as Administration three times
    /// out of three, from its topic.
    @Test("a neutral sentence keeps the remembered audience, not a guess from the topic")
    func neutralKeepsMemory() async throws {
        let text = "The meeting room on the third floor is closed on Friday."
        #expect(try await hits(text, (.students, false), fallback: .students) >= 2)
    }
}
