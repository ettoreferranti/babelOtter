import Foundation
import Testing

@testable import BabelOtterKit

/// Replays scripted chunks, and records what it was asked for.
///
/// Chunks rather than lines, and deliberately split mid-line in places: a real
/// socket does not respect message boundaries, and a fake that always hands
/// over tidy lines would test the client against a transport that cannot exist.
private final class FakeTransport: OllamaTransport, @unchecked Sendable {
    private let scripted: [String]
    private let failure: (any Error)?
    private(set) var requestedURLs: [URL] = []
    private(set) var bodies: [Data?] = []

    init(chunks: [String], failure: (any Error)? = nil) {
        self.scripted = chunks
        self.failure = failure
    }

    func chunks(from url: URL, body: Data?) async throws -> AsyncThrowingStream<String, any Error> {
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

/// Records whether its own stream was told the consumer is gone -- standing
/// in for "the request was actually stopped" without depending on
/// `URLSessionTransport`, which cannot be exercised in CI (it needs a real
/// daemon; see its own doc comment).
private final class TerminationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var isTerminated = false

    func markTerminated() {
        lock.lock()
        isTerminated = true
        lock.unlock()
    }

    private var terminated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isTerminated
    }

    /// Polls in short steps rather than sleeping a fixed duration: fast when
    /// termination already landed, bounded when it never does.
    func waitForTermination(timeoutNanoseconds: UInt64 = 500_000_000) async -> Bool {
        let step: UInt64 = 5_000_000
        var waited: UInt64 = 0
        while waited < timeoutNanoseconds {
            if terminated { return true }
            try? await Task.sleep(nanoseconds: step)
            waited += step
        }
        return terminated
    }
}

/// A transport whose stream yields once and then never finishes on its own --
/// exactly what a real generation in flight looks like from `OllamaClient`'s
/// side. Only cancellation can end it; this is how the test proves that
/// cancellation actually reaches "the network" rather than merely stopping
/// the caller from listening.
private final class NeverEndingTransport: OllamaTransport, @unchecked Sendable {
    let recorder = TerminationRecorder()

    func chunks(from url: URL, body: Data?) async throws -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            continuation.onTermination = { [recorder] _ in recorder.markTerminated() }
            continuation.yield(
                #"{"message":{"role":"assistant","content":"a"},"done":false}"# + "\n")
        }
    }
}

@Suite("Ollama client")
struct OllamaClientTests {

    private static func fixtureChunks() throws -> [String] {
        let url = SourceTree.repositoryRoot
            .appending(path: "Tests/Fixtures/ollama/chat-stream.ndjson")
        let text = try String(contentsOf: url, encoding: .utf8)
        // Split at an arbitrary point mid-stream, so framing is exercised.
        let midpoint = text.index(text.startIndex, offsetBy: text.count / 2)
        return [String(text[..<midpoint]), String(text[midpoint...])]
    }

    @Test("a fixture-backed chat yields the deltas, then finishes")
    func chatReplaysFixture() async throws {
        let transport = FakeTransport(chunks: try Self.fixtureChunks())
        let client = OllamaClient(endpoint: .loopback, transport: transport)

        var events: [StreamEvent] = []
        for try await event in client.chat(model: "m", messages: [.init(role: "user", content: "hi")]) {
            events.append(event)
        }

        #expect(events.last == .finished)
        let text = events.reduce(into: "") { result, event in
            if case .delta(let piece) = event { result += piece }
        }
        #expect(text == #"{"detected_source": "en", "blocks": ["Guten Morgen"]}"#)
    }

    @Test("the chat URL is loopback, and names the chat endpoint")
    func chatURLIsLoopback() async throws {
        let transport = FakeTransport(chunks: try Self.fixtureChunks())
        let client = OllamaClient(endpoint: .loopback, transport: transport)
        for try await _ in client.chat(model: "m", messages: []) {}

        let url = try #require(transport.requestedURLs.first)
        #expect(url.host() == "127.0.0.1")
        #expect(url.path().hasSuffix("/api/chat"))
        #expect(url.scheme == "http")
    }

    @Test("the request body carries the model and asks for streaming")
    func chatBodyIsAStreamingRequest() async throws {
        let transport = FakeTransport(chunks: try Self.fixtureChunks())
        let client = OllamaClient(endpoint: .loopback, transport: transport)
        for try await _ in client.chat(model: "mistral-small3.2:24b", messages: []) {}

        let body = try #require(transport.bodies.first ?? nil)
        let decoded = try JSONDecoder().decode(ChatRequest.self, from: body)
        #expect(decoded.model == "mistral-small3.2:24b")
        #expect(decoded.stream == true)
    }

    @Test("a transport failure surfaces rather than ending the stream quietly")
    func transportFailurePropagates() async throws {
        let transport = FakeTransport(
            chunks: [], failure: OllamaTransportError.unreachable(detail: "refused"))
        let client = OllamaClient(endpoint: .loopback, transport: transport)

        await #expect(throws: OllamaTransportError.self) {
            for try await _ in client.chat(model: "m", messages: []) {}
        }
    }

    @Test("a malformed line is surfaced as an event, and the stream continues")
    func malformedLineDoesNotStopTheStream() async throws {
        let transport = FakeTransport(chunks: [
            #"{"message":{"role":"assistant","content":"a"},"done":false}"# + "\n",
            "not json at all\n",
            #"{"message":{"role":"assistant","content":"b"},"done":false}"# + "\n",
            #"{"message":{"role":"assistant","content":""},"done":true}"# + "\n",
        ])
        let client = OllamaClient(endpoint: .loopback, transport: transport)

        var events: [StreamEvent] = []
        for try await event in client.chat(model: "m", messages: []) { events.append(event) }

        #expect(events.contains(.malformed(line: "not json at all")))
        #expect(events.contains(.delta("b")), "the stream must continue past a bad line")
        #expect(events.last == .finished)
    }

    @Test("a final line with no trailing newline is not lost")
    func finalLineWithoutNewlineSurvives() async throws {
        let transport = FakeTransport(chunks: [
            #"{"message":{"role":"assistant","content":"only"},"done":false}"#
        ])
        let client = OllamaClient(endpoint: .loopback, transport: transport)

        var events: [StreamEvent] = []
        for try await event in client.chat(model: "m", messages: []) { events.append(event) }
        #expect(events == [.delta("only")])
    }

    @Test("health reports ready when the daemon holds the configured model")
    func healthReady() async {
        let transport = FakeTransport(chunks: [
            #"{"models":[{"name":"m","size":1}]}"#
        ])
        let client = OllamaClient(endpoint: .loopback, transport: transport)
        #expect(await client.health(configuredModel: "m") == .ready)
    }

    @Test("health reports the missing model rather than failing")
    func healthModelMissing() async {
        let transport = FakeTransport(chunks: [#"{"models":[]}"#])
        let client = OllamaClient(endpoint: .loopback, transport: transport)
        #expect(await client.health(configuredModel: "m") == .modelMissing("m"))
    }

    /// #45: a health check never fails loudly. Every failure has to become a
    /// status the menu bar can render, or the caller needs its own error
    /// handling for the thing whose job is reporting errors.
    @Test("health turns an unreachable daemon into a status, not a thrown error")
    func healthNeverThrows() async {
        let transport = FakeTransport(
            chunks: [], failure: OllamaTransportError.unreachable(detail: "refused"))
        let client = OllamaClient(endpoint: .loopback, transport: transport)
        let status = await client.health(configuredModel: "m")
        #expect(status.readiness == .blocked)
        #expect(status.detail.contains("refused"))
    }

    @Test("health turns a bad HTTP status into a readable explanation")
    func healthExplainsHTTPFailures() async {
        let transport = FakeTransport(chunks: [], failure: OllamaTransportError.httpStatus(503))
        let client = OllamaClient(endpoint: .loopback, transport: transport)
        #expect(await client.health(configuredModel: "m").detail.contains("503"))
    }

    @Test("health on an unparseable catalogue is blocked, not silently ready")
    func healthOnGarbage() async {
        let transport = FakeTransport(chunks: ["this is not json"])
        let client = OllamaClient(endpoint: .loopback, transport: transport)
        #expect(await client.health(configuredModel: "m").readiness == .blocked)
    }

    /// NFR-P1: a chat request carries the user's selected text. Building a
    /// value must not transmit it -- a stream created and then dropped during
    /// a UI rebuild, an error path or a test has to send nothing.
    @Test("building a chat stream transmits nothing until it is iterated")
    func chatIsLazy() async throws {
        let transport = FakeTransport(chunks: try Self.fixtureChunks())
        let client = OllamaClient(endpoint: .loopback, transport: transport)

        _ = client.chat(model: "m", messages: [.init(role: "user", content: "secret")])
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(transport.requestedURLs.isEmpty)

        for try await _ in client.chat(model: "m", messages: []) {}
        #expect(transport.requestedURLs.count == 1)
    }

    /// A generation the consumer stopped listening to (Escape, a timeout)
    /// must not keep running underneath. Before the fix, `chat`'s own `Task`
    /// had no `onTermination` wired up, so cancelling the caller never
    /// reached the transport at all -- the request kept running forever.
    @Test("cancelling the consumer stops the request rather than leaving it running")
    func cancellingConsumerStopsTheRequest() async throws {
        let transport = NeverEndingTransport()
        let client = OllamaClient(endpoint: .loopback, transport: transport)

        let task = Task {
            var iterator = client.chat(model: "m", messages: []).makeAsyncIterator()
            _ = try? await iterator.next()  // the one event the transport ever yields
            _ = try? await iterator.next()  // parks here until cancelled
        }

        // Let the consuming task actually reach the second, parked await
        // before cancelling it, so cancellation lands mid-stream rather than
        // before anything began.
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()

        let terminated = await transport.recorder.waitForTermination()
        #expect(terminated, "cancelling the consumer must reach the transport, not leave it running")
    }

    @Test("installed models are read from the tags endpoint")
    func installedModels() async throws {
        let transport = FakeTransport(chunks: [
            #"{"models":[{"name":"mistral-small3.2:24b","size":15000000000}]}"#
        ])
        let client = OllamaClient(endpoint: .loopback, transport: transport)
        let models = try await client.installedModels()

        #expect(models.map(\.name) == ["mistral-small3.2:24b"])
        #expect(try #require(transport.requestedURLs.first).path().hasSuffix("/api/tags"))
        #expect(transport.bodies.first ?? nil == nil, "a catalogue read sends no body")
    }
}
