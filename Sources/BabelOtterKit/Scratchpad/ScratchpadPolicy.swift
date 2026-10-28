import Foundation

/// Where a scratchpad run stands (#84).
public enum ScratchpadStatus: Sendable, Equatable {
    /// Nothing run yet, or the text was cleared.
    case idle
    /// `chunk` counts from zero.
    case running(chunk: Int, of: Int)
    case finished
    /// Stopped, timed out or failed after `done` of `of` chunks. `reason` is
    /// nil when the user pressed Stop.
    case interrupted(done: Int, of: Int, reason: String?)
}

/// Everything a scratchpad result depends on, so a changed one marks it out
/// of date and a Continue never mixes two settings in one text.
public struct ScratchpadSettings: Sendable, Equatable {
    public var action: Action
    public var source: String
    /// Translate: the target picked, nil for automatic.
    public var target: LanguageCode?
    /// Translate: a direction set by Swap, which wins over detection.
    public var swapped: Direction?
    /// The audience picked; nil lets Translate infer it.
    public var profileID: String?
    public var styleNote: String
    /// The answer to "Which language is this?", when it was asked.
    public var language: LanguageCode?

    public init(
        action: Action, source: String, target: LanguageCode? = nil, swapped: Direction? = nil,
        profileID: String? = nil, styleNote: String = "", language: LanguageCode? = nil
    ) {
        self.action = action
        self.source = source
        self.target = target
        self.swapped = swapped
        self.profileID = profileID
        self.styleNote = styleNote
        self.language = language
    }
}

/// What the scratchpad's buttons allow, from its state alone (#84).
public struct ScratchpadPolicy: Sendable, Equatable {

    /// Explain is never chunked (an explanation of one part loses the text's
    /// point), so it has a cap instead.
    public static let explainLimit = 6_000

    public let status: ScratchpadStatus
    public let current: ScratchpadSettings
    /// The settings of the result on screen; nil before the first run.
    public let ran: ScratchpadSettings?
    /// Why no text may be sent now, such as the built-in server starting.
    public let serverProblem: String?

    public init(
        status: ScratchpadStatus, current: ScratchpadSettings, ran: ScratchpadSettings?,
        serverProblem: String?
    ) {
        self.status = status
        self.current = current
        self.ran = ran
        self.serverProblem = serverProblem
    }

    public var isRunning: Bool {
        guard case .running = status else { return false }
        return true
    }

    /// Chunks of an interrupted run that are already on screen.
    private var interruptedDone: Int {
        guard case .interrupted(let done, let total, _) = status else { return 0 }
        if done >= total { return 0 }
        return done
    }

    private var isUnchanged: Bool {
        ran == current
    }

    /// Run becomes Continue after an interruption with some chunks done,
    /// while nothing has changed.
    public var continues: Bool {
        guard interruptedDone > 0 else { return false }
        return isUnchanged
    }

    public var runTitle: String {
        if continues { return "Continue" }
        return "Run"
    }

    private var isBlank: Bool {
        current.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isTooLongToExplain: Bool {
        guard case .explain = current.action else { return false }
        return current.source.count > Self.explainLimit
    }

    public var canRun: Bool {
        if isRunning { return false }
        if isBlank { return false }
        if isTooLongToExplain { return false }
        return serverProblem == nil
    }

    public var canStop: Bool { isRunning }

    /// Copy takes a whole result only.
    public var canCopy: Bool {
        guard case .finished = status else { return false }
        return true
    }

    /// A result, whole or partial, is on screen.
    private var hasResult: Bool {
        switch status {
        case .finished: return true
        case .interrupted(let done, _, _): return done > 0
        case .idle, .running: return false
        }
    }

    /// The result on screen was made with other settings or another text.
    public var isOutOfDate: Bool {
        guard hasResult else { return false }
        return !isUnchanged
    }

    /// The line the bar shows about why Run is off, if it is not obvious.
    public var problem: String? {
        if isTooLongToExplain {
            return "Explain works on up to 6,000 characters. "
                + "Shorten the text, or explain a part of it."
        }
        return serverProblem
    }

    /// The bar's progress line.
    ///
    /// Guards rather than a switch with returns inside its cases: muter's
    /// rewrite of such a switch does not compile.
    public var progress: String? {
        if case .running(let chunk, let total) = status {
            return runningLine(chunk, total)
        }
        guard case .interrupted(let done, let total, let reason) = status else { return nil }
        if let reason { return reason }
        return stoppedLine(done, total)
    }

    private func runningLine(_ chunk: Int, _ total: Int) -> String {
        if total > 1 { return "Part \(chunk + 1) of \(total)\u{2026}" }
        return "Working\u{2026}"
    }

    private func stoppedLine(_ done: Int, _ total: Int) -> String {
        if total > 1 { return "Stopped after \(done) of \(total) parts." }
        return "Stopped."
    }
}
