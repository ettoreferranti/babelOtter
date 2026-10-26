import Foundation

/// The setup window's steps, in order (#70, `FR-ONB-01`). The Ollama step
/// is part of Model since #126: with the built-in server there is no Ollama
/// to install.
public enum SetupStep: Int, Sendable, CaseIterable, Comparable {
    case accessibility
    case model
    case hotkeys
    case tryIt

    public var title: String {
        switch self {
        case .accessibility: return "Accessibility"
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
    /// The model server in use (#126).
    public var server: ModelServer
    /// The built-in server's state; nil when the user's own Ollama is in use.
    public var builtInServer: BuiltInServerState?
    /// The server in use, as probed. Nil while the first check is under way.
    public var daemon: DaemonProbe?
    /// The user's own Ollama on its default port, probed whichever server is
    /// in use, to offer it when it already has the model (#126).
    public var ownOllama: DaemonProbe?
    public var chosenModel: String
    public var testSucceeded: Bool

    public init(
        accessibilityGranted: Bool, server: ModelServer = .own, builtInServer: BuiltInServerState? = nil,
        daemon: DaemonProbe?, ownOllama: DaemonProbe? = nil, chosenModel: String, testSucceeded: Bool
    ) {
        self.accessibilityGranted = accessibilityGranted
        self.server = server
        self.builtInServer = builtInServer
        self.daemon = daemon
        self.ownOllama = ownOllama
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
        case .model:
            if facts.server == .builtIn { return builtInBlocker(facts) }
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

    /// The Model step on the built-in server: running, answering, and with
    /// the model downloaded (#126).
    private static func builtInBlocker(_ facts: SetupFacts) -> String? {
        switch facts.builtInServer ?? .stopped {
        case .stopped, .starting:
            return BuiltInServerState.starting.status
        case .failed(let reason):
            return BuiltInServerState.failed(reason).status
        case .running:
            break
        }
        guard case .reachable(let models)? = facts.daemon else { return BuiltInServerState.starting.status }
        if models.contains(facts.chosenModel) { return nil }
        return "Download \(displayName(of: facts.chosenModel)) to continue."
    }

    /// "Mistral Small 3.2" for the built-in model, the name for any other.
    public static func displayName(of model: String) -> String {
        if model == BuiltInServer.model { return BuiltInServer.modelDisplayName }
        return model
    }

    /// True when the user's own Ollama already has the built-in model, so
    /// the Model step offers it instead of a 15 GB download (#126).
    public static func offersOwnOllama(_ facts: SetupFacts) -> Bool {
        guard case .reachable(let models)? = facts.ownOllama else { return false }
        return models.contains(BuiltInServer.model)
    }

    /// The server a fresh install starts setup with, once its own Ollama has
    /// been probed: that Ollama when it already has the model, else built-in.
    public static func initialServer(ownOllama: DaemonProbe) -> ModelServer {
        guard case .reachable(let models) = ownOllama else { return .builtIn }
        if models.contains(BuiltInServer.model) { return .own }
        return .builtIn
    }
}

/// Whether the setup window opens by itself at launch (#70).
///
/// The answer is kept in its own flag rather than read from config.json,
/// because the first launch writes config.json: a fresh user who closed
/// the window early must see it again, though the file now exists.
public enum SetupGate {

    /// What to store when the flag is not set yet: done for an install
    /// that already had config.json, pending for a fresh one.
    public static func initialCompleted(configurationExisted: Bool) -> Bool {
        configurationExisted
    }

    /// `setupCompleted` nil: never decided, which `initialCompleted`
    /// answers. Otherwise open until Finish set it true.
    public static func shouldOpen(configurationExisted: Bool, setupCompleted: Bool?) -> Bool {
        guard let setupCompleted else { return !initialCompleted(configurationExisted: configurationExisted) }
        return !setupCompleted
    }
}
