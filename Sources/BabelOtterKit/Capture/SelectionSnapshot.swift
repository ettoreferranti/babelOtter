import Foundation

/// Which application a selection came from.
///
/// Recorded at trigger time, because by the time the user presses Replace the
/// frontmost application is babelOtter's own popup (`FR-CAP-01`).
public struct SourceApplication: Sendable, Equatable {
    public let processIdentifier: Int32
    public let bundleIdentifier: String?
    public let name: String

    public init(processIdentifier: Int32, bundleIdentifier: String?, name: String) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}

/// Everything a capture has to carry for the rest of the action to work.
///
/// **No `AXUIElement`, and no selected range.** `FR-CAP-01` originally asked
/// for both, so that replacement could write back to the element it read from.
/// Replacement now always goes through the clipboard -- Accessibility writes
/// were measured returning `.success` while changing nothing on every web
/// surface tried -- so there is nothing left to write back *to*. Dropping them
/// keeps this type `Sendable` without an `@unchecked`, keeps CoreFoundation out
/// of the package's public API, and removes a handle that could go stale
/// between capture and replace. See `docs/architecture.md` section 7.
///
/// The text is a ``UserText``: a snapshot is the most log-attractive value in
/// the app, and NFR-P3 makes it unloggable without deliberate redaction.
public struct SelectionSnapshot: Sendable, Equatable {

    public let text: UserText
    public let tier: CaptureTier
    public let application: SourceApplication
    public let capturedAt: Date

    public init(
        text: UserText,
        tier: CaptureTier,
        application: SourceApplication,
        capturedAt: Date = Date()
    ) {
        self.text = text
        self.tier = tier
        self.application = application
        self.capturedAt = capturedAt
    }

    /// Whitespace-only counts as empty (`FR-CAP-06`), matching ``UserText``.
    public var isEmpty: Bool { text.isEmpty }

    /// Whether this capture put the user's text on the pasteboard, which is
    /// what the popup has to disclose (`NFR-P9`).
    public var usedPasteboard: Bool { tier.usesPasteboard }
}
