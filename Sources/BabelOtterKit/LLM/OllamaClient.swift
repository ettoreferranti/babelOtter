import Foundation

/// The only file in this package permitted to touch the network.
///
/// `Config/networking-allowlist.txt` names it, and `NetworkingCallSiteTests`
/// fails the build if a second file references a networking symbol. NFR-P4 is
/// the reason: babelOtter's promise that it opens no non-loopback connection is
/// only provable while there is one place to look.
///
/// Every URL is built from an ``OllamaEndpoint``, which makes a non-loopback
/// host unrepresentable. The client deliberately accepts no host, port or URL
/// from a caller -- that is what turns "we only talk to loopback" from a
/// convention into a property of the type system.
public struct OllamaClient: Sendable {

    private let endpoint: OllamaEndpoint
    private let transport: any OllamaTransport

    public init(endpoint: OllamaEndpoint = .loopback, transport: any OllamaTransport) {
        self.endpoint = endpoint
        self.transport = transport
    }

    /// A client wired to the real transport, for callers that must not spell
    /// `URLSessionTransport` themselves.
    ///
    /// `NetworkingCallSiteTests` scans every file under `Sources/` -- app
    /// included -- for networking symbol names, substring-matched on purpose
    /// (see that suite's docs). `URLSessionTransport` contains `URLSession` as
    /// a substring, so a caller outside this allowlisted file that constructs
    /// one directly trips the guard. This factory keeps that construction
    /// here, where it is reviewed and allowlisted, instead of adding a second
    /// allowlist entry for a caller that only ever wants the real transport.
    public static func loopback(timeout: TimeInterval) -> OllamaClient {
        OllamaClient(transport: URLSessionTransport(timeout: timeout))
    }

    /// Streams a chat completion as classified events.
    ///
    /// Chunks from the transport are framed here rather than there, so a
    /// transport handing over a half-finished line is handled by
    /// ``NDJSONFramer`` -- code with tests -- instead of by whatever the URL
    /// loading system does that day.
    public func chat(model: String, messages: [ChatMessage]) -> LazyStream<StreamEvent> {
        let endpoint = endpoint
        let transport = transport
        return LazyStream { AsyncThrowingStream { continuation in
            Task {
                do {
                    let body = try JSONEncoder().encode(
                        ChatRequest(model: model, messages: messages, stream: true))
                    let stream = try await transport.chunks(
                        from: endpoint.url(path: "api/chat"), body: body)

                    var framer = NDJSONFramer()
                    for try await chunk in stream {
                        for line in framer.consume(chunk) {
                            continuation.yield(OllamaWire.event(from: line))
                        }
                    }
                    // The last line of a stream that ended without a newline.
                    for line in framer.finish() {
                        continuation.yield(OllamaWire.event(from: line))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        } }
    }

    /// What is installed locally, for `FR-OLL-03`'s missing-model check.
    public func installedModels() async throws -> [InstalledModel] {
        let text = try await collect(from: endpoint.url(path: "api/tags"), body: nil)
        return try JSONDecoder.responseContract
            .decode(TagsResponse.self, from: Data(text.utf8))
            .models
    }

    /// Streams progress while the daemon downloads a model (`FR-OLL-03`).
    ///
    /// **This does not weaken NFR-P2.** babelOtter posts to
    /// `127.0.0.1/api/pull`; the *Ollama daemon* makes the outbound
    /// connection. babelOtter's own egress stays loopback-only, which is why
    /// #46's last acceptance criterion is that the architecture test still
    /// reports exactly one call site afterwards.
    ///
    /// Nothing is requested until the returned stream is iterated, so a user
    /// who declines the confirmation causes no download -- the decline is the
    /// absence of a call, not a cancellation of one.
    public func pull(model: String) -> LazyStream<PullProgress> {
        let endpoint = endpoint
        let transport = transport
        return LazyStream { AsyncThrowingStream { continuation in
            Task {
                do {
                    let body = try JSONEncoder().encode(PullRequest(name: model, stream: true))
                    let stream = try await transport.chunks(
                        from: endpoint.url(path: "api/pull"), body: body)

                    var framer = NDJSONFramer()
                    var emitted = 0
                    for try await chunk in stream {
                        emitted += yieldProgress(framer.consume(chunk), to: continuation)
                    }
                    emitted += yieldProgress(framer.finish(), to: continuation)

                    // A pull that reported nothing at all is not a success.
                    // Finishing quietly here would leave the UI showing a
                    // progress bar that never moved and never ended.
                    guard emitted > 0 else {
                        continuation.finish(throwing: OllamaTransportError.undecodableBody)
                        return
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        } }
    }

    /// Decodes progress lines, skipping any the daemon words differently than
    /// expected. A pull is long and noisy, and abandoning a 15GB download over
    /// one unrecognised status line would be a poor trade.
    private func yieldProgress(
        _ lines: [String], to continuation: AsyncThrowingStream<PullProgress, any Error>.Continuation
    ) -> Int {
        var count = 0
        for line in lines {
            guard
                let progress = try? JSONDecoder.responseContract.decode(
                    PullProgress.self, from: Data(line.utf8))
            else { continue }
            continuation.yield(progress)
            count += 1
        }
        return count
    }

    /// Whether the daemon is up and holds the model this action needs.
    ///
    /// Deliberately non-throwing. #45 wants a health check that never blocks
    /// and never fails loudly -- it exists to tell the menu bar what to show,
    /// and a health check that can itself error just moves the problem. Every
    /// failure becomes a status the UI already knows how to render.
    public func health(configuredModel: String) async -> DaemonStatus {
        let probe: DaemonProbe
        do {
            probe = .reachable(models: try await installedModels().map(\.name))
        } catch let error as OllamaTransportError {
            probe = .unreachable(detail: Self.describe(error))
        } catch {
            probe = .unreachable(detail: error.localizedDescription)
        }
        return DaemonStatusPolicy().status(probe: probe, configuredModel: configuredModel)
    }

    private static func describe(_ error: OllamaTransportError) -> String {
        switch error {
        case .unreachable(let detail): return detail
        case .httpStatus(let code): return "the daemon answered with HTTP \(code)"
        case .undecodableBody: return "the daemon's reply was not text"
        }
    }

    /// Drains a non-streaming response into one string.
    private func collect(from url: URL, body: Data?) async throws -> String {
        var text = ""
        for try await chunk in try await transport.chunks(from: url, body: body) {
            text += chunk
        }
        return text
    }
}

/// The real transport. The only type in babelOtter that opens a connection.
///
/// It cannot be unit-tested in CI, because it needs a daemon listening; the
/// behaviour that *can* be tested -- framing, classification, URL construction,
/// error propagation -- lives above it behind ``OllamaTransport`` and is
/// covered there. What remains here is deliberately as thin as it can be, on
/// the principle that untestable code should be small enough to read.
public struct URLSessionTransport: OllamaTransport {

    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 60) {
        self.timeout = timeout
    }

    /// An ephemeral session: no cookie store, no credential store, no on-disk
    /// cache. babelOtter talks to one loopback daemon and has nothing to
    /// remember between calls, so a session that persists anything is a place
    /// user content could come to rest without anyone deciding it should.
    private var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }

    public func chunks(from url: URL, body: Data?) async throws -> AsyncThrowingStream<
        String, any Error
    > {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            // Nothing listening is the common case and deserves the actionable
            // message, not a generic failure. FR-OLL-02 turns this into an
            // offer to start Ollama.
            throw OllamaTransportError.unreachable(detail: error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OllamaTransportError.httpStatus(http.statusCode)
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // `lines` strips the terminator; the framer above expects
                    // them, and re-adding one keeps that contract explicit
                    // rather than depending on what this type happens to yield.
                    for try await line in bytes.lines {
                        continuation.yield(line + "\n")
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
