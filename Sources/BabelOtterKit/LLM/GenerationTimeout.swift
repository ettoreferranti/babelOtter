import Foundation

/// Why a generation stopped early.
public enum CancellationReason: String, Sendable, Equatable, CaseIterable {
    case timedOut
    case userRequested

    /// Something the user can act on, not a status code.
    public var detail: String {
        switch self {
        case .timedOut:
            return
                "The model timed out. Try again, or choose a smaller model in Settings."
        case .userRequested:
            return "Cancelled."
        }
    }
}

/// What to do with a generation in flight.
public enum GenerationOutcome: Sendable, Equatable {
    case proceed
    case cancel(CancellationReason)
    case completed

    /// `NFR-PERF-3` and `FR-UI-07` both require that a cancelled request
    /// applies no partial result. Making it a property of the outcome rather
    /// than a rule at the call site means it cannot be forgotten in one of the
    /// several places cancellation is handled.
    public var discardsPartialResult: Bool {
        switch self {
        case .cancel: return true
        case .proceed, .completed: return false
        }
    }

    /// Only a finished generation is written to history. A cancelled one leaves
    /// no trace, which is `FR-UI-07`, and an in-flight one has nothing to write
    /// yet.
    public var writesHistory: Bool {
        switch self {
        case .completed: return true
        case .proceed, .cancel: return false
        }
    }
}

/// Decides whether a generation should still be running.
///
/// A pure function of elapsed time and user intent, so the rule is provable
/// without a test that waits sixty seconds. The clock belongs to the caller.
public struct GenerationTimeout: Sendable {

    public let timeoutSeconds: Double

    public init(timeoutSeconds: Double) {
        self.timeoutSeconds = timeoutSeconds
    }

    public init(configuration: Configuration) {
        self.init(timeoutSeconds: configuration.timeoutSeconds)
    }

    public func decide(elapsed: Double, userDismissed: Bool) -> GenerationOutcome {
        // The user's intent outranks the clock, and is reported as theirs. A
        // dismissal reported as a timeout would tell them the model was slow
        // when in fact they pressed Escape.
        if userDismissed { return .cancel(.userRequested) }

        // A hand-edited configuration can carry zero or a negative value, and
        // cancelling every generation the instant it starts is not a defensible
        // reading of that. Treated as "no clock limit" instead.
        guard timeoutSeconds > 0 else { return .proceed }

        // `>=` and not `>`: at exactly the configured timeout, the budget is
        // spent. Stated because a mutant flipping it must be killed, and
        // `exactlyAtTimeout` sits on the boundary to do it.
        guard elapsed >= timeoutSeconds else { return .proceed }
        return .cancel(.timedOut)
    }
}
