import Foundation
import Testing

@testable import BabelOtterKit

/// Talks to a real Ollama daemon. Local only.
///
/// CI runners have no daemon and no models, and this repository is public, so
/// nothing resembling real user text should execute on a third-party runner
/// (NFR-P8). Enable with:
///
///     BABELOTTER_INTEGRATION=1 swift test --filter OllamaIntegrationTests
///
/// These are the tests that would have caught a wrong assumption about the
/// wire format. Everything above them is proven against a fixture, which proves
/// the code matches the fixture -- not that the fixture matches Ollama.
@Suite("Integration: a real Ollama daemon", .enabled(if: IntegrationGate.isEnabled))
struct OllamaIntegrationTests {

    private var client: OllamaClient {
        OllamaClient(endpoint: .loopback, transport: URLSessionTransport(timeout: 120))
    }

    @Test("the daemon is reachable and reports its catalogue")
    func daemonIsReachable() async throws {
        let models = try await client.installedModels()
        #expect(!models.isEmpty, "no models installed; run `ollama pull` first")
        for model in models {
            #expect(!model.name.isEmpty)
        }
    }

    @Test("health reports ready for a model that is installed")
    func healthForInstalledModel() async throws {
        let installed = try await client.installedModels()
        let name = try #require(installed.first?.name)
        #expect(await client.health(configuredModel: name) == .ready)
    }

    @Test("health reports the missing model for one that is not")
    func healthForMissingModel() async {
        let status = await client.health(configuredModel: "definitely-not-installed:0b")
        #expect(status == .modelMissing("definitely-not-installed:0b"))
        #expect(status.readiness == .degraded)
    }

    /// The real shape check. If Ollama's stream ever stops matching
    /// `Tests/Fixtures/ollama/chat-stream.ndjson`, this is what says so.
    @Test("a real generation streams deltas and finishes")
    func realGenerationStreams() async throws {
        let installed = try await client.installedModels()
        let model = try #require(installed.first?.name)

        var text = ""
        var finished = false
        var malformed: [String] = []

        for try await event in client.chat(
            model: model,
            messages: [
                ChatMessage(role: "user", content: "Reply with exactly: ok"),
            ])
        {
            switch event {
            case .delta(let piece): text += piece
            case .finished: finished = true
            case .malformed(let line): malformed.append(line)
            }
        }

        #expect(finished, "the stream never reported done")
        #expect(!text.isEmpty, "no content arrived")
        #expect(malformed.isEmpty, "unrecognised lines: \(malformed)")
    }

    /// The pipeline end to end against a real model, which is the only place
    /// the prompt and the parser meet reality.
    @Test("a translate prompt comes back as parseable JSON with the right block count")
    func translateRoundTrip() async throws {
        let installed = try await client.installedModels()
        let model = try #require(installed.first?.name)

        let blocks = ["Good morning.", "How are you?"]
        let prompt = PromptBuilder().build(
            PromptRequest(
                action: .translate,
                source: .english,
                target: .swissGerman,
                profile: .colleagues,
                blocks: blocks))

        var raw = ""
        for try await event in client.chat(
            model: model, messages: [ChatMessage(role: "user", content: prompt)])
        {
            if case .delta(let piece) = event { raw += piece }
        }

        guard case .decoded(let response) = ResponseParser.parseTranslate(raw) else {
            Issue.record("model output did not parse as a translate response:\n\(raw)")
            return
        }
        #expect(response.blocks.count == blocks.count,
            "block count drifted; BlockCountPolicy would retry here")
        #expect(!response.blocks.contains { $0.contains("\u{00DF}") },
            "FR-TRN-05: eszett must not survive to a de-CH target")
    }
}
