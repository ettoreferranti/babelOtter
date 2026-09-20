import Foundation

/// A finished generation, ready to be shown or put back.
public struct GeneratedResult: Sendable, Equatable {
    public let text: UserText
    public let action: Action
    /// Whether capture used the pasteboard, which the popup discloses
    /// (`NFR-P9`).
    public let capturedViaPasteboard: Bool

    public init(text: UserText, action: Action, capturedViaPasteboard: Bool) {
        self.text = text
        self.action = action
        self.capturedViaPasteboard = capturedViaPasteboard
    }
}

/// What the interface must do with a result.
public struct Custody: Sendable, Equatable {
    /// `nil` only when there is genuinely nothing to keep.
    public let result: GeneratedResult?
    public let offersCopy: Bool
    public let keepsPopupOpen: Bool
    public let message: String?
}

/// Decides what happens to a generated result, on every path.
///
/// #34 and `FR-CAP-05`: a result the user waited for is never silently lost.
/// The claim is about *every* error path, which is only provable if the paths
/// are enumerable -- so the outcomes are closed enums and the tests are
/// exhaustive over them. Spot-checking a property claimed over all paths is how
/// the one unchecked path ends up being the one that drops the result.
public enum ResultCustody {

    public static func afterReplacement(
        _ outcome: ReplacementOutcome, result: GeneratedResult
    ) -> Custody {
        Custody(
            // Always kept, whatever happened.
            result: result,
            // Always offered, including after a paste: a paste cannot be
            // confirmed, so withdrawing Copy would strand a user whose paste
            // silently failed.
            offersCopy: true,
            // A paste that appeared to work lets the popup go. Anything else
            // has something to tell the user, and closing over it would be the
            // silent loss #34 forbids.
            keepsPopupOpen: outcome != .pasted,
            message: outcome.detail)
    }

    /// The source application quitting mid-generation is not a reason to
    /// discard anything. The user still waited for this, and can still copy it.
    public static func afterSourceQuit(result: GeneratedResult) -> Custody {
        afterReplacement(
            .notAttempted(reason: "The application the text came from has closed."),
            result: result)
    }

    /// The one case with nothing to keep.
    ///
    /// A cancelled generation has no result by definition (`NFR-PERF-3`,
    /// `FR-UI-07`), which is why this is a separate entry point rather than an
    /// outcome with a `nil` result threaded through the others -- an optional
    /// there would invite every caller to handle a case that only arises here.
    public static func afterCancellation(_ reason: CancellationReason) -> Custody {
        Custody(result: nil, offersCopy: false, keepsPopupOpen: false, message: reason.detail)
    }
}

/// Whether an action should run at all.
public enum ActionPrecondition {

    /// `FR-CAP-06` and #35. A selection that is empty or whitespace-only is
    /// reported and nothing else happens: no request to the model, and nothing
    /// written to history. The point of checking here rather than after
    /// generation is that the model is never called, so the user is not left
    /// waiting on a request that was never worth making.
    public static func refusal(for snapshot: SelectionSnapshot) -> CaptureRefusal? {
        snapshot.isEmpty ? .nothingSelected : nil
    }
}
