import Foundation

/// Everything on the pasteboard, by type, for every item.
///
/// Types are `String` rather than `NSPasteboard.PasteboardType` so this can
/// live in the kit, which may not import AppKit (NFR-Q3). The app target
/// bridges.
public struct PasteboardSnapshot: Sendable, Equatable {
    public let items: [[String: Data]]

    public init(items: [[String: Data]]) {
        self.items = items
    }

    public static let empty = PasteboardSnapshot(items: [])
}

/// The pasteboard, narrowed to what capture and replacement need.
public protocol Pasteboard: Sendable {
    var changeCount: Int { get }
    /// Every type of every item, so a restore is faithful rather than
    /// string-shaped.
    func snapshot() -> PasteboardSnapshot
    func restore(_ snapshot: PasteboardSnapshot)
    func readString() -> String?
    /// `concealed` sets `org.nspasteboard.ConcealedType` and
    /// `com.apple.is-sensitive`. Measured 2026-09-20: these do **not** stop
    /// Universal Clipboard. They are set because clipboard managers honour
    /// them, which keeps the user's text out of a clipboard history app.
    func write(_ string: String, concealed: Bool)
    /// Blocks until `changeCount` differs from `previous`, or the timeout
    /// elapses. Returns whether it moved.
    func awaitChange(from previous: Int, timeout: Double) -> Bool
}

/// Synthetic Command-C and Command-V.
///
/// The methods are named `copy` and `paste` rather than anything built on the
/// verb "to dispatch", because the networking guard matches that verb followed
/// by an open parenthesis and does not exempt comments. Writing the spelling
/// out here to explain the choice is itself enough to fail the build, which is
/// the third time that has happened and is the guard behaving as intended.
public protocol KeystrokeSending: Sendable {
    func copy()
    func paste()
}

public enum ClipboardError: Error, Equatable {
    /// `changeCount` never moved. The only signal a capture worked.
    case nothingCaptured
    /// It moved, but no text arrived.
    case noTextOnPasteboard
}

/// Whether to accept a capture attempt, try again, or stop.
public enum ClipboardDecision: Sendable, Equatable {
    case accept
    case retry
    case giveUp
}

/// The retry rule, as a pure function of what happened and how many attempts
/// have been made.
///
/// Measured 2026-09-20: three of seven captures produced nothing on the first
/// attempt. Whether that was empty selections or the pasteboard not catching up
/// is unresolved, and one retry costs a fraction of a second while telling the
/// two apart in the logs.
public struct ClipboardPolicy: Sendable {

    public let retryTimeout: Double

    public init(retryTimeout: Double = 4.0) {
        self.retryTimeout = retryTimeout
    }

    /// `attempt` is zero-based: 0 is the first Command-C.
    public func decide(changeCountMoved: Bool, attempt: Int) -> ClipboardDecision {
        if changeCountMoved { return .accept }
        guard attempt == 0 else { return .giveUp }
        return .retry
    }
}

/// Capture through the clipboard: save, Command-C, read, restore.
///
/// Pure orchestration over the two protocols above, so the part that matters
/// most runs in CI. The restore is in a `defer` deliberately: `NFR-P10` makes
/// it a privacy mechanism rather than a courtesy, because Universal Clipboard
/// transfers at paste time and the restore is what ends the exposure. A
/// `defer` cannot be skipped by a path somebody adds later, which is exactly
/// how this obligation would otherwise be lost.
public struct ClipboardCapture: Sendable {

    private let pasteboard: any Pasteboard
    private let keystrokes: any KeystrokeSending
    private let policy: ClipboardPolicy
    private let firstTimeout: Double

    public init(
        pasteboard: any Pasteboard,
        keystrokes: any KeystrokeSending,
        policy: ClipboardPolicy = ClipboardPolicy(),
        firstTimeout: Double = 2.0
    ) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.policy = policy
        self.firstTimeout = firstTimeout
    }

    public func capture() -> Result<String, ClipboardError> {
        let saved = pasteboard.snapshot()
        defer { pasteboard.restore(saved) }

        var attempt = 0
        while true {
            let before = pasteboard.changeCount
            keystrokes.copy()

            var timeout = firstTimeout
            if attempt > 0 { timeout = policy.retryTimeout }
            let moved = pasteboard.awaitChange(from: before, timeout: timeout)

            switch policy.decide(changeCountMoved: moved, attempt: attempt) {
            case .accept:
                // `changeCount` moved, so something arrived -- but it may not
                // be text. Reading without checking the count is the defect
                // that pasted 36 characters of unrelated older clipboard
                // content into a live Mail message during probe development.
                guard let text = pasteboard.readString(), !text.isEmpty else {
                    return .failure(.noTextOnPasteboard)
                }
                return .success(text)
            case .retry:
                attempt += 1
            case .giveUp:
                return .failure(.nothingCaptured)
            }
        }
    }
}

/// Replacement through the clipboard: activate, write, Command-V, restore.
public struct ClipboardReplacement: Sendable {

    private let pasteboard: any Pasteboard
    private let keystrokes: any KeystrokeSending

    public init(pasteboard: any Pasteboard, keystrokes: any KeystrokeSending) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
    }

    /// `activateSource` re-activates the application the selection came from
    /// (`FR-CAP-03`); it returns whether that succeeded. It is a closure
    /// because activation is AppKit's business and this type is in the kit.
    public func replace(
        with text: String, activateSource: () -> Bool
    ) -> ReplacementOutcome {
        guard !text.isEmpty else {
            return .notAttempted(reason: "There is nothing to paste.")
        }
        guard activateSource() else {
            return .notAttempted(
                reason: "The application the text came from is no longer available.")
        }

        let saved = pasteboard.snapshot()
        defer { pasteboard.restore(saved) }

        pasteboard.write(text, concealed: true)
        keystrokes.paste()
        return .pasted
    }
}
