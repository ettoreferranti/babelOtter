import Foundation

/// The only address babelOtter is permitted to talk to.
///
/// NFR-P1 says no user content leaves the machine. The App Sandbox cannot enforce
/// that for us -- `com.apple.security.network.client` is all-or-nothing with no
/// loopback-only variant, and denying it would block Ollama too. So the guarantee
/// lives here: a non-loopback endpoint is unrepresentable, and the architecture
/// guard in `NetworkingCallSiteTests` asserts that every network call in the
/// package goes through a value of this type.
public struct OllamaEndpoint: Sendable, Equatable, Hashable {

    /// Ollama's default port.
    public static let defaultPort = 11_434

    /// Exactly the literal loopback addresses. Nothing here is a *name*, so
    /// nothing here can be redirected by the resolver.
    ///
    /// `localhost` is deliberately absent, and deliberately still accepted:
    /// ``normalize(_:)`` rewrites it to `127.0.0.1` before this check. It is a
    /// name resolved through `/etc/hosts` and the system resolver, neither of
    /// which this type controls, and neither of which guarantees loopback -- so
    /// storing it in ``host`` would mean the stored value's destination is
    /// decided elsewhere. Rewriting instead of rejecting keeps
    /// `OllamaEndpoint(host: "localhost")` working for callers while making
    /// ``host`` always an address a resolver cannot point anywhere else.
    ///
    /// `0.0.0.0` is deliberately absent: it is a wildcard *bind* address, not a
    /// loopback destination.
    private static let permittedHosts: Set<String> = ["127.0.0.1", "::1"]

    public let host: String
    public let port: Int

    /// Fails for any host that is not loopback, or any port outside 1...65535.
    public init?(host: String, port: Int = OllamaEndpoint.defaultPort) {
        let normalized = Self.normalize(host)
        guard Self.permittedHosts.contains(normalized) else { return nil }
        guard (1...65_535).contains(port) else { return nil }
        self.host = normalized
        self.port = port
    }

    private static func normalize(_ host: String) -> String {
        var value = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // `!inner.isEmpty` rather than `value.count > 2`: it states the thing
        // being guarded against -- a bare "[]" unwrapping to nothing -- instead
        // of encoding it as a length, and it keeps a relational operator out of
        // a comma-conjunction condition, which muter mis-splices.
        if value.hasPrefix("["), value.hasSuffix("]") {
            let inner = value.dropFirst().dropLast()
            if !inner.isEmpty { value = String(inner) }
        }
        // The one name this type accepts becomes the address it stands for, so
        // `host` is never something the resolver could send elsewhere. See
        // `permittedHosts`.
        if value == "localhost" { return "127.0.0.1" }
        return value
    }

    /// The endpoint babelOtter always uses.
    public static let loopback = OllamaEndpoint(host: "127.0.0.1")!

    /// Always returns ``loopback``, whatever the environment says.
    ///
    /// The parameter exists so tests can prove the environment is ignored, and so
    /// the intent is visible at the call site. `OLLAMA_HOST` is never honoured:
    /// a remote value there would ship the user's writing off the machine.
    public static func resolved(ignoring environment: [String: String]) -> OllamaEndpoint {
        return .loopback
    }

    /// `http://127.0.0.1:11434`, with IPv6 hosts bracketed.
    public var baseURL: URL {
        // if/else rather than a ternary: muter's SwapTernary operator
        // intermittently emits invalid Swift here, and because every mutant for
        // a file compiles into one binary, that one bad mutant makes the whole
        // file unmeasurable and fails the gate. Observed as a buildError on one
        // run and a clean result on the next -- the flakiness recorded in
        // docs/HANDOFF.md, now pinned to this line.
        var hostComponent = host
        if host.contains(":") { hostComponent = "[\(host)]" }
        guard let url = URL(string: "http://\(hostComponent):\(port)") else {
            preconditionFailure("loopback host \(host):\(port) must form a valid URL")
        }
        return url
    }

    /// `baseURL` joined with an API path, tolerant of a leading slash.
    public func url(path: String) -> URL {
        baseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}
