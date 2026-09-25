import Foundation

/// How the client gets bytes back from the daemon.
///
/// The seam is expressed in `URL` and `Data` on purpose. Foundation's URL
/// loading types are symbols `NetworkingCallSiteTests` refuses outside the one
/// allowlisted file, so naming any of them here would either fail the build or
/// force the allowlist to grow -- and the allowlist growing is precisely what
/// NFR-P4 exists to prevent. They stay inside `OllamaClient.swift`, and this
/// protocol describes the shape of the conversation rather than the machinery.
///
/// The guard matches spelling and does not exempt comments, which is why this
/// note describes those types instead of naming them. That is the conservative
/// direction deliberately: a scanner that understood context is one a real
/// call site could hide behind.
///
/// Chunks are *raw* text, not lines. The client frames them with
/// ``NDJSONFramer``, so a transport that hands over a half-finished line -- as
/// any real socket eventually will -- is handled by code CI can prove, rather
/// than by whatever the URL loading system happens to do that day.
public protocol OllamaTransport: Sendable {
    func chunks(from url: URL, body: Data?) async throws -> AsyncThrowingStream<String, any Error>
}

/// What went wrong talking to the daemon, in terms a user could act on.
public enum OllamaTransportError: Error, Equatable {
    /// Nothing is listening. `FR-OLL-02` turns this into "start Ollama".
    case unreachable(detail: String)
    /// Reached it, and it said no.
    case httpStatus(Int)
    /// The body was not text.
    case undecodableBody
}
