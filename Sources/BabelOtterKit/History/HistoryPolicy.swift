import Foundation

/// What history does under the configuration in use (#69, `FR-HIS-03`).
///
/// A fallback configuration -- the defaults, because config.json could not
/// be read -- pauses history whatever it says: the defaults record for 90
/// days, so following them would let a typo undo "off", and deleting by them
/// would cut short a user's "unlimited".
public enum HistoryPolicy: Equatable, Sendable {
    /// Record; delete what is older than `.days`.
    case keep(HistoryRetention)
    /// The user's "off": record nothing, delete nothing.
    case off
    /// The configuration is a fallback: record nothing, delete nothing.
    case paused

    public init(retention: HistoryRetention, configurationIsFallback: Bool) {
        if configurationIsFallback {
            self = .paused
            return
        }
        switch retention {
        case .off: self = .off
        case .days, .unlimited: self = .keep(retention)
        }
    }

    public var records: Bool {
        guard case .keep = self else { return false }
        return true
    }

    /// Records dated before this are deleted now; nil when none may be.
    public func pruneCutoff(now: Date) -> Date? {
        guard case .keep(let retention) = self else { return nil }
        return retention.cutoff(now: now)
    }

    /// The menu's line above History...; nil while recording.
    public var menuNote: String? {
        switch self {
        case .keep: return nil
        case .off: return "History: off"
        case .paused: return "History: off until config.json is fixed"
        }
    }

    /// The History window's line above the list; nil while recording.
    public var windowNote: String? {
        switch self {
        case .keep: return nil
        case .off: return "History is off - nothing new is saved."
        case .paused: return "History is off until config.json is fixed - nothing new is saved."
        }
    }
}
