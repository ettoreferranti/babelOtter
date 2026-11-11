import Foundation

/// The weekly learning goal (#136): `learning` in config.json. Optional
/// there, and each field optional inside it: what is missing is the
/// default, on with three days.
public struct LearningSettings: Sendable, Equatable, Codable {

    public static let daysRange: ClosedRange<Int> = 1...7
    public static let `default` = LearningSettings(enabled: true, daysPerWeek: 3)
    static let expected = "expected a number of days from 1 to 7"

    /// Off: nothing is counted and nothing is shown; what was earned stays.
    public var enabled: Bool
    /// Learning days a calendar week for the goal to be met.
    public var daysPerWeek: Int

    public init(enabled: Bool, daysPerWeek: Int) {
        self.enabled = enabled
        self.daysPerWeek = daysPerWeek
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case daysPerWeek
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? Self.default.enabled
        daysPerWeek = try container.decodeIfPresent(Int.self, forKey: .daysPerWeek) ?? Self.default.daysPerWeek
        if !Self.daysRange.contains(daysPerWeek) {
            throw DecodingError.dataCorruptedError(
                forKey: .daysPerWeek, in: container, debugDescription: Self.expected)
        }
    }
}
