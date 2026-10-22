import Foundation

/// The setup window's steps, in order (#70, `FR-ONB-01`).
public enum SetupStep: Int, Sendable, CaseIterable, Comparable {
    case accessibility
    case ollama
    case model
    case hotkeys
    case tryIt

    public var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .ollama: return "Ollama"
        case .model: return "Model"
        case .hotkeys: return "Hotkeys"
        case .tryIt: return "Try it"
        }
    }

    public static func < (lhs: SetupStep, rhs: SetupStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What the setup window knows right now.
public struct SetupFacts: Sendable, Equatable {
    public var accessibilityGranted: Bool
    /// Nil while the first check is under way.
    public var daemon: DaemonProbe?
    public var chosenModel: String
    public var testSucceeded: Bool

    public init(accessibilityGranted: Bool, daemon: DaemonProbe?, chosenModel: String, testSucceeded: Bool) {
        self.accessibilityGranted = accessibilityGranted
        self.daemon = daemon
        self.chosenModel = chosenModel
        self.testSucceeded = testSucceeded
    }
}

/// Whether a step may be left forward, and if not, why (#70). All the
/// wording is here, so it is tested.
public enum SetupFlow {

    public static let sampleSentence = "Please register for the module by Friday."

    /// Nil when Continue (or Finish) may be pressed.
    public static func blocker(for step: SetupStep, facts: SetupFacts) -> String? {
        switch step {
        case .accessibility:
            if facts.accessibilityGranted { return nil }
            return "Grant Accessibility to continue."
        case .ollama:
            guard let daemon = facts.daemon else { return "Checking Ollama\u{2026}" }
            guard case .reachable = daemon else { return "Ollama isn't running." }
            return nil
        case .model:
            guard let daemon = facts.daemon else { return "Checking Ollama\u{2026}" }
            guard case .reachable(let models) = daemon else { return "Ollama isn't running." }
            if models.contains(facts.chosenModel) { return nil }
            return "\(facts.chosenModel) is not installed."
        case .hotkeys:
            return nil
        case .tryIt:
            if facts.testSucceeded { return nil }
            return "Translate the sentence to finish."
        }
    }
}

/// Whether the setup window opens by itself at launch (#70).
public enum SetupGate {

    /// Only a fresh install: no config.json at launch, and setup never
    /// finished. An existing install is not interrupted.
    public static func shouldOpen(configurationExisted: Bool, setupCompleted: Bool) -> Bool {
        if configurationExisted { return false }
        return !setupCompleted
    }
}
