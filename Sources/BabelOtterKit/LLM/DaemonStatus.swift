import Foundation

/// What a health probe found, before any judgement is applied to it.
public enum DaemonProbe: Sendable, Equatable {
    case reachable(models: [String])
    case unreachable(detail: String)
}

/// How ready babelOtter is, at the granularity the menu bar shows (`FR-UI-03`).
public enum Readiness: Sendable, Equatable, CaseIterable {
    case ready
    case degraded
    case blocked
}

/// The daemon's state, as the rest of the app needs to understand it.
public enum DaemonStatus: Sendable, Equatable {
    case ready
    /// Reachable, but the model this action is configured to use is not
    /// installed. `FR-OLL-03` offers to pull it.
    case modelMissing(String)
    /// Nothing listening. `FR-OLL-02` offers to start Ollama.
    case unreachable(detail: String)

    public var readiness: Readiness {
        switch self {
        case .ready: return .ready
        case .modelMissing: return .degraded
        case .unreachable: return .blocked
        }
    }

    /// Degraded is not blocked: a missing model is one confirmation away from
    /// working, whereas an unreachable daemon needs the user to go and do
    /// something. Both refuse to generate, and they refuse differently.
    public var canGenerate: Bool {
        switch self {
        case .ready: return true
        case .modelMissing, .unreachable: return false
        }
    }

    public var detail: String {
        switch self {
        case .ready:
            return "Ollama is running and the configured model is installed."
        case .modelMissing(let model):
            return "Ollama is running, but the model \(model) is not installed."
        case .unreachable(let detail):
            return "Ollama is not reachable on \(OllamaEndpoint.loopback.baseURL): \(detail)"
        }
    }
}

/// Turns a probe into a status.
///
/// Pure, and deliberately holding no state. #45 requires that status recovers
/// without a restart, and the simplest way to guarantee that is to have nothing
/// to recover *from*: every answer is computed from the probe in front of it. A
/// cached "blocked" is exactly how an app comes to need restarting.
public struct DaemonStatusPolicy: Sendable {

    public init() {}

    public func status(probe: DaemonProbe, configuredModel: String) -> DaemonStatus {
        switch probe {
        case .unreachable(let detail):
            return .unreachable(detail: detail)
        case .reachable(let models):
            // Exact match: a tag is part of a model's identity, and
            // `mistral-small3.2:latest` is not necessarily the same weights as
            // `mistral-small3.2:24b`. Treating them as interchangeable would
            // silently run a different model than the one evaluated.
            guard models.contains(configuredModel) else {
                return .modelMissing(configuredModel)
            }
            return .ready
        }
    }
}
