import Foundation

/// How long history keeps a record (#69, `FR-HIS-03`): `retentionDays` in
/// config.json, a number of days, "unlimited" or "off".
public enum HistoryRetention: Sendable, Equatable, Codable {
    /// Records older than this many days (1 or more) are deleted.
    case days(Int)
    case unlimited
    /// Nothing new is recorded; what is there stays until Clear All.
    case off

    public static let `default` = HistoryRetention.days(90)

    static let secondsPerDay: Double = 86_400
    static let expected = "expected a number of days (1 or more), \"unlimited\" or \"off\""

    /// Records dated before this are deleted; nil when none are.
    public func cutoff(now: Date) -> Date? {
        guard case .days(let days) = self else { return nil }
        // In Double: a huge number of days cannot overflow.
        return now.addingTimeInterval(-Double(days) * Self.secondsPerDay)
    }

    /// The words are read trimmed and in any case: "Off" is off.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let days = try? container.decode(Int.self) {
            if days >= 1 {
                self = .days(days)
                return
            }
        } else if let word = try? container.decode(String.self) {
            switch word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "unlimited":
                self = .unlimited
                return
            case "off":
                self = .off
                return
            default:
                break
            }
        }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: Self.expected))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .days(let days): try container.encode(days)
        case .unlimited: try container.encode("unlimited")
        case .off: try container.encode("off")
        }
    }
}
