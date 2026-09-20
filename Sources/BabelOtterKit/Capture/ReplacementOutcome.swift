import Foundation

/// What happened when a result was put back.
///
/// There is no `replaced` case, and its absence is the design.
///
/// Replacement goes through the clipboard, and a Command-V has no read-back: the
/// selection collapses to a caret, so there is nothing left to compare against.
/// In the applications that need the clipboard most -- Teams, Word, OneNote, VS
/// Code -- Accessibility cannot read the result either. So babelOtter cannot
/// know whether a paste landed.
///
/// Reporting "Replaced" on that basis is precisely the failure
/// `docs/architecture.md` section 7 item 2 records: the user is told their text
/// was replaced while it sits untouched. There the false signal came from the
/// OS; here it would come from us, which is worse.
public enum ReplacementOutcome: Sendable, Equatable {
    /// Command-V was sent. Whether the application accepted it is not
    /// observable.
    case pasted
    /// It was tried and something went wrong before the keystroke.
    case failed(reason: String)
    /// Never tried -- the source application has gone, or the user chose Copy.
    case notAttempted(reason: String)

    /// `FR-CAP-05` and #34: the result is never discarded, whatever happened.
    public var retainsResult: Bool { true }

    /// **Always true**, including after a paste. Since a paste cannot be
    /// confirmed, withdrawing Copy afterwards would strand a user whose paste
    /// silently failed -- holding a result they waited for and can no longer
    /// reach.
    public var offersCopy: Bool { true }

    public var detail: String? {
        switch self {
        case .pasted: return nil
        case .failed(let reason), .notAttempted(let reason): return reason
        }
    }
}
