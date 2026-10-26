import Foundation

/// The built-in server as the menu and Settings describe it (#126).
public enum BuiltInServerState: Sendable, Equatable {
    case stopped
    case starting
    case running
    /// Stopped by itself and not restarted; the reason is worded for "The
    /// built-in server stopped: ...".
    case failed(String)

    /// The status line under the mode in Settings.
    public var status: String {
        switch self {
        case .stopped: return "The built-in server isn't running."
        case .starting: return "Starting the built-in server\u{2026}"
        case .running: return "Built-in server running"
        case .failed(let reason): return "The built-in server stopped: \(reason)"
        }
    }
}

/// What the controller has to do after an event.
public enum BuiltInServerEffect: Sendable, Equatable {
    case none
    case launch
    case terminate
}

/// When the built-in server starts, stops and restarts (#126). Pure: the
/// controller feeds it events and carries out the effect it returns.
public struct BuiltInServerPolicy: Sendable, Equatable {

    /// A second unexpected exit within this long leaves the server stopped.
    public static let restartWindow: TimeInterval = 60

    public private(set) var state: BuiltInServerState = .stopped
    /// Set by `stop()`, so the exit that follows is not taken for a crash.
    private var stopping = false
    /// Set by `restart()` on a live server: its exit starts the next one.
    private var restarting = false
    private var lastUnexpectedExit: Date?

    public init() {}

    /// At launch, on switching to Built-in, and for the Restart remedy,
    /// which also forgets an earlier crash.
    public mutating func start() -> BuiltInServerEffect {
        switch state {
        case .starting, .running:
            return .none
        case .stopped, .failed:
            if case .failed = state { lastUnexpectedExit = nil }
            stopping = false
            state = .starting
            return .launch
        }
    }

    /// At quit, and on switching to the user's own Ollama.
    public mutating func stop() -> BuiltInServerEffect {
        restarting = false
        switch state {
        case .stopped, .failed:
            state = .stopped
            return .none
        case .starting, .running:
            stopping = true
            state = .stopped
            return .terminate
        }
    }

    /// The Restart remedy: a live server that doesn't answer is stopped
    /// and started again; a stopped or failed one is started.
    public mutating func restart() -> BuiltInServerEffect {
        switch state {
        case .stopped, .failed:
            return start()
        case .starting, .running:
            stopping = true
            restarting = true
            state = .starting
            return .terminate
        }
    }

    /// The server never answered in time: it is stopped, and stays failed
    /// with the reason until Restart.
    public mutating func timedOut(after seconds: Int) -> BuiltInServerEffect {
        guard state == .starting else { return .none }
        restarting = false
        stopping = true
        state = .failed("it didn't answer within \(seconds) seconds.")
        return .terminate
    }

    /// The process could not be started at all: no restart, which would
    /// fail the same way.
    public mutating func launchFailed(_ reason: String) {
        stopping = false
        state = .failed(reason)
    }

    /// The process could not be started because the binary is not in this
    /// build: a development build made without `Tools/fetch-ollama.sh`.
    public static let missingBinary = "the bundled Ollama is missing from this build."

    /// The server answered on its port.
    public mutating func reachable() {
        if state == .starting { state = .running }
    }

    /// The process ended. `lastLogLine` is the last non-empty line it wrote.
    public mutating func exited(status: Int32, lastLogLine: String?, at now: Date) -> BuiltInServerEffect {
        if stopping {
            stopping = false
            if restarting {
                restarting = false
                lastUnexpectedExit = nil
                state = .starting
                return .launch
            }
            // A server stopped for not answering keeps saying why.
            if case .failed = state { return .none }
            state = .stopped
            return .none
        }
        if Self.portInUse(lastLogLine) {
            state = .failed(
                "Port \(OllamaEndpoint.builtInPort) is in use by another program.")
            return .none
        }
        if let previous = lastUnexpectedExit {
            if now.timeIntervalSince(previous) < Self.restartWindow {
                state = .failed(Self.reason(status: status, lastLogLine: lastLogLine))
                return .none
            }
        }
        lastUnexpectedExit = now
        state = .starting
        return .launch
    }

    static func portInUse(_ line: String?) -> Bool {
        guard let line else { return false }
        return line.lowercased().contains("address already in use")
    }

    /// Longest log excerpt the status line quotes.
    static let excerptLength = 160

    static func reason(status: Int32, lastLogLine: String?) -> String {
        let base = "it exited with status \(status)."
        guard let line = lastLogLine?.trimmingCharacters(in: .whitespacesAndNewlines) else { return base }
        if line.isEmpty { return base }
        var excerpt = String(line.prefix(excerptLength))
        if line.count > excerptLength { excerpt += "\u{2026}" }
        return "\(base) Last log line: \(excerpt)"
    }

    /// The pid recorded by an earlier run that should be terminated before
    /// starting: only when that process is still our bundled binary, so a
    /// pid reused by another program is never touched.
    public static func leftover(
        pidFile: String?, bundledExecutable: String, executableOf: (Int32) -> String?
    ) -> Int32? {
        guard let text = pidFile?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        guard let pid = Int32(text) else { return nil }
        guard pid > 1 else { return nil }
        guard executableOf(pid) == bundledExecutable else { return nil }
        return pid
    }

    /// The last non-empty line of a log, for `exited`.
    public static func lastLine(of log: String) -> String? {
        let lines = log.split(whereSeparator: \.isNewline)
        let line = lines.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return line.map(String.init)
    }
}
