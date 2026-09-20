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

    /// Streams a chat completion as classified events.
    ///
    /// Chunks from the transport are framed here rather than there, so a
    /// transport handing over a half-finished line is handled by
    /// ``NDJSONFramer`` -- code with tests -- instead of by whatever the URL
    /// loading system does that day.
    public func chat(model: String, messages: [ChatMessage]) -> AsyncThrowingStream<
        StreamEvent, any Error
    > {
        let endpoint = endpoint
        let transport = transport
        return AsyncThrowingStream { continuation in
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
        }
    }

    /// What is installed locally, for `FR-OLL-03`'s missing-model check.
    public func installedModels() async throws -> [InstalledModel] {
        let text = try await collect(from: endpoint.url(path: "api/tags"), body: nil)
        return try JSONDecoder.responseContract
            .decode(TagsResponse.self, from: Data(text.utf8))
            .models
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
