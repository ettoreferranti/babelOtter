import Foundation

/// Which Ollama lingoSwen talks to (#126).
///
/// `builtIn` is the copy inside the app, run by lingoSwen on its own port
/// with its own models folder; `own` is an Ollama the user installed, on
/// Ollama's default port. Both are loopback: the choice is which local
/// server, never whether the text leaves the Mac.
public enum ModelServer: String, Sendable, Codable, CaseIterable {
    case builtIn
    case own

    /// The name Settings and the Privacy panel show.
    public var displayName: String {
        switch self {
        case .builtIn: return "Built-in"
        case .own: return "My own Ollama"
        }
    }

    public var endpoint: OllamaEndpoint {
        switch self {
        case .builtIn: return .builtIn
        case .own: return .loopback
        }
    }
}
