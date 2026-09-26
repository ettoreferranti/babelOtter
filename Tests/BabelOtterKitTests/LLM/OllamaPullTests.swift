import Foundation
import Testing

@testable import BabelOtterKit

private final class RecordingTransport: OllamaTransport, @unchecked Sendable {
    private let scripted: [String]
    private let failure: (any Error)?
    private(set) var callCount = 0
    private(set) var requestedURLs: [URL] = []
    private(set) var bodies: [Data?] = []

    init(chunks: [String], failure: (any Error)? = nil) {
        self.scripted = chunks
        self.failure = failure
    }

    func chunks(from url: URL, body: Data?) async throws -> AsyncThrowingStream<String, any Error> {
        callCount += 1
        requestedURLs.append(url)
        bodies.append(body)
        if let failure { throw failure }
        let lines = scripted
        return AsyncThrowingStream { continuation in
            for chunk in lines { continuation.yield(chunk) }
            continuation.finish()
        }
    }
}

/// `.timeLimit`: muter has no per-mutant timeout, and a mutant that deletes a
/// `continuation.finish()` leaves every stream here open forever. Without a
/// limit one such mutant stalls the whole mutation job until CI cancels it,
/// which is what happened to every run from the M1a shell onward. With it,
/// the hang is a failure -- a killed mutant -- after a minute.
@Suite("Pulling a model through the local daemon", .timeLimit(.minutes(1)))
struct OllamaPullTests {

    private static func fixture() throws -> String {
        try String(
            contentsOf: SourceTree.repositoryRoot
                .appending(path: "Tests/Fixtures/ollama/pull-stream.ndjson"),
            encoding: .utf8)
    }

    @Test("a pull reports increasing progress and ends in success")
    func reportsProgress() async throws {
        let transport = RecordingTransport(chunks: [try Self.fixture()])
        let client = OllamaClient(endpoint: .loopback, transport: transport)

        var updates: [PullProgress] = []
        for try await progress in client.pull(model: "mistral-small3.2:24b") {
            updates.append(progress)
        }

        #expect(updates.last?.isComplete == true)
        let fractions = updates.compactMap(\.fraction)
        #expect(fractions == [0.0, 0.5, 1.0])
    }

    @Test("status lines without byte counts report no fraction rather than a made-up one")
    func statusLinesWithoutCounts() async throws {
        let transport = RecordingTransport(chunks: [try Self.fixture()])
        let client = OllamaClient(endpoint: .loopback, transport: transport)

        var withoutCounts: [String] = []
        for try await progress in client.pull(model: "m") where progress.fraction == nil {
            withoutCounts.append(progress.status)
        }
        #expect(withoutCounts.contains("verifying sha256 digest"))
        #expect(withoutCounts.contains("pulling manifest"))
    }

    /// #46: declining the confirmation downloads nothing. The decline is the
    /// absence of a call, not the cancellation of one, so nothing may be
    /// requested until the stream is iterated.
    @Test("a pull that is never iterated makes no request at all")
    func decliningDownloadsNothing() async throws {
        let transport = RecordingTransport(chunks: [try Self.fixture()])
        let client = OllamaClient(endpoint: .loopback, transport: transport)

        _ = client.pull(model: "m")
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(transport.callCount == 0)
    }

    @Test("the pull URL is loopback and the body names the model")
    func pullRequestShape() async throws {
        let transport = RecordingTransport(chunks: [try Self.fixture()])
        let client = OllamaClient(endpoint: .loopback, transport: transport)
        for try await _ in client.pull(model: "mistral-small3.2:24b") {}

        let url = try #require(transport.requestedURLs.first)
        #expect(url.host() == "127.0.0.1")
        #expect(url.path().hasSuffix("/api/pull"))

        let body = try #require(transport.bodies.first ?? nil)
        #expect(try JSONDecoder().decode(PullRequest.self, from: body).name
            == "mistral-small3.2:24b")
    }

    @Test("an unrecognised status line is skipped rather than abandoning the download")
    func unrecognisedLinesAreSkipped() async throws {
        let transport = RecordingTransport(chunks: [
            "{\"status\":\"pulling manifest\"}\n",
            "not json at all\n",
            "{\"status\":\"success\"}\n",
        ])
        let client = OllamaClient(endpoint: .loopback, transport: transport)

        var updates: [PullProgress] = []
        for try await progress in client.pull(model: "m") { updates.append(progress) }
        #expect(updates.map(\.status) == ["pulling manifest", "success"])
    }

    /// A progress bar that never moves and never ends is worse than an error.
    @Test("a pull that reports nothing at all fails rather than finishing quietly")
    func silentPullIsAFailure() async {
        let transport = RecordingTransport(chunks: ["garbage\n", "more garbage\n"])
        let client = OllamaClient(endpoint: .loopback, transport: transport)

        await #expect(throws: OllamaTransportError.self) {
            for try await _ in client.pull(model: "m") {}
        }
    }

    @Test("a transport failure during a pull surfaces")
    func transportFailurePropagates() async {
        let transport = RecordingTransport(
            chunks: [], failure: OllamaTransportError.unreachable(detail: "refused"))
        let client = OllamaClient(endpoint: .loopback, transport: transport)

        await #expect(throws: OllamaTransportError.self) {
            for try await _ in client.pull(model: "m") {}
        }
    }
}
