import Foundation

/// Why a capture produced nothing.
///
/// The two cases need different messages, which is the whole reason they are
/// separate. "Nothing was selected" is the user's own doing and needs only a
/// note; "this application cannot be read without the clipboard" is a refusal
/// babelOtter made on their behalf, and they may want to reconsider the
/// setting that caused it.
public enum CaptureRefusal: Sendable, Equatable {
    /// `FR-CAP-06`. Not an error.
    case nothingSelected
    /// Strict capture-only mode, and no Accessibility tier worked here.
    case clipboardRefused(application: String)

    public var detail: String {
        switch self {
        case .nothingSelected:
            return "Nothing is selected."
        case .clipboardRefused(let application):
            return
                "\(application) cannot be read without the clipboard, and strict capture is on. "
                + "Turn it off in Settings to use babelOtter here."
        }
    }

    /// Whether the user could change a setting and have this work.
    public var isSettingDependent: Bool {
        switch self {
        case .nothingSelected: return false
        case .clipboardRefused: return true
        }
    }
}

/// Which capture tiers are permitted, and what to say when none of them work.
///
/// **Capture-only strict mode**, not the Accessibility-only mode #77 originally
/// described. That one assumed the clipboard was an avoidable fallback;
/// replacement now always uses it, so refusing the clipboard outright would
/// mean an app that can read but never write. What is worth offering is an
/// asymmetry: refuse the clipboard for *reading*, accept it for *writing*.
///
/// The asymmetry is defensible rather than a fudge. Reading puts the user's
/// **existing** text on the pasteboard -- an email they received, a document
/// they did not write. Writing puts babelOtter's **own output** there, which
/// they have just seen and approved. The exposure is genuinely different.
///
/// The cost is in `docs/architecture.md` section 7: strict capture means no
/// capture at all in Teams, Word, OneNote or VS Code.
public struct CapturePolicy: Sendable {

    public let strictCaptureOnly: Bool

    public init(strictCaptureOnly: Bool) {
        self.strictCaptureOnly = strictCaptureOnly
    }

    public init(configuration: Configuration) {
        self.init(strictCaptureOnly: configuration.strictCaptureOnly)
    }

    /// The tiers the ladder may attempt.
    public var allowedTiers: [CaptureTier] {
        guard strictCaptureOnly else { return CaptureTier.allCases }
        return CaptureTier.allCases.filter { !$0.usesPasteboard }
    }

    /// Why nothing was captured, given what the ladder was allowed to try.
    ///
    /// In strict mode a failure is ambiguous from the ladder's point of view --
    /// the clipboard was never attempted, so "nothing selected" and "this app
    /// needs the clipboard" look identical. The distinction has to be made
    /// here, by asking whether the clipboard *would* have been available.
    public func refusal(
        application: String, clipboardWouldHaveBeenTried: Bool
    ) -> CaptureRefusal {
        guard strictCaptureOnly, clipboardWouldHaveBeenTried else { return .nothingSelected }
        return .clipboardRefused(application: application)
    }
}
