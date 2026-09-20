import Foundation

public enum BlockCountDecision: Sendable, Equatable {
    case accept
    /// Try once more, sending the whole text rather than the blocks.
    case retryWholeText
    /// Give up on structure and say so (`NFR-REL-2`).
    case degrade(reason: String)
}

/// Decides what to do when the model returns the wrong number of blocks.
///
/// A pure function of `(expected, received, attempt)` rather than a stateful
/// retrier, so "no more than one retry is ever issued" is a property provable by
/// exhaustion instead of by reading the call site and hoping. The caller owns
/// the attempt counter; this owns the rule.
public struct BlockCountPolicy: Sendable {

    public init() {}

    /// `attempt` is zero-based: 0 is the first response, 1 is the response to
    /// the single retry.
    public func decide(expected: Int, received: Int, attempt: Int) -> BlockCountDecision {
        guard expected != received else { return .accept }
        guard attempt == 0 else {
            return .degrade(
                reason:
                    "The model returned \(received) block(s) where \(expected) were expected, "
                    + "twice. Structure could not be preserved."
            )
        }
        return .retryWholeText
    }
}
