import Foundation

/// A calendar day as the learning log keeps it (#136): year, month and day
/// in one number, 20261111. No time of day.
public struct LearningDay: Sendable, Hashable, Comparable, Codable {

    public let number: Int

    public init(number: Int) {
        self.number = number
    }

    /// The day `date` falls on in `calendar`.
    public init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        number = (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    /// Noon of the day, so a change of clocks cannot move it to another.
    public func date(calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(
            year: number / 10_000, month: number / 100 % 100, day: number % 100, hour: 12))
    }

    public static func < (lhs: LearningDay, rhs: LearningDay) -> Bool {
        lhs.number < rhs.number
    }

    /// A bare number in the stored log.
    public init(from decoder: any Decoder) throws {
        number = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(number)
    }
}

/// A milestone and the day it was earned.
public struct EarnedMilestone: Sendable, Equatable, Codable {
    public let milestone: Milestone
    public let day: LearningDay

    public init(milestone: Milestone, day: LearningDay) {
        self.milestone = milestone
        self.day = day
    }
}

/// What the learning goal remembers (#136): days, two totals, the
/// milestones earned and the day of the last hint. Never text.
public struct LearningLog: Sendable, Equatable, Codable {

    /// The most recent learning days kept. At seven days a week that is 57
    /// weeks, the longest streak the log can then show.
    public static let maximumDays = 400

    /// Oldest first, each day once.
    public private(set) var days: [LearningDay] = []
    public private(set) var wordsCorrected = 0
    public private(set) var explanations = 0
    /// In the order earned.
    public private(set) var earned: [EarnedMilestone] = []
    public private(set) var lastHintDay: LearningDay?

    public init() {}

    /// Nothing counted and nothing earned.
    public var isEmpty: Bool {
        if !days.isEmpty { return false }
        return earned.isEmpty
    }

    public func has(_ day: LearningDay) -> Bool {
        days.contains(day)
    }

    public mutating func add(_ day: LearningDay) {
        if has(day) { return }
        days.append(day)
        days.sort()
        if days.count > Self.maximumDays { days.removeFirst(days.count - Self.maximumDays) }
    }

    public mutating func addWords(_ count: Int) {
        wordsCorrected += count
    }

    public mutating func addExplanation() {
        explanations += 1
    }

    public func hasEarned(_ milestone: Milestone) -> Bool {
        for entry in earned where entry.milestone == milestone {
            return true
        }
        return false
    }

    /// Each milestone is earned once.
    public mutating func earn(_ milestone: Milestone, on day: LearningDay) {
        if hasEarned(milestone) { return }
        earned.append(EarnedMilestone(milestone: milestone, day: day))
    }

    public mutating func hintShown(on day: LearningDay) {
        lastHintDay = day
    }
}
