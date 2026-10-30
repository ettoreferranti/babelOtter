import Foundation

extension ErrorCategory {
    /// The name Progress shows (#78).
    public var displayName: String {
        switch self {
        case .grammaticalCase: return "Case"
        case .wordOrder: return "Word order"
        case .gender: return "Gender"
        case .agreement: return "Agreement"
        case .falseFriend: return "False friend"
        case .spelling: return "Spelling"
        case .register: return "Register"
        case .preposition: return "Preposition"
        case .other: return "Other"
        }
    }
}

/// The span Progress looks at, and the one before it for the trend (#78).
public enum ProgressPeriod: Int, Sendable, CaseIterable {
    case week = 7
    case month = 30
    case quarter = 90

    public var days: Int { rawValue }

    public var title: String {
        switch self {
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        case .quarter: return "Last 90 days"
        }
    }

    /// One chart point per day for a week, else per week.
    public var bucketDays: Int {
        switch self {
        case .week: return 1
        case .month, .quarter: return 7
        }
    }
}

/// How a rate moved against the period before (#78).
public enum ProgressTrend: Sendable, Equatable {
    case down(from: Double)
    case up(from: Double)
    case steady
}

/// One chart point: the rate in a day or week, nil when nothing was
/// corrected in it.
public struct ProgressPoint: Sendable, Equatable {
    public let start: Date
    public let rate: Double?
}

/// One error category in the period.
public struct ProgressRow: Sendable, Equatable {
    public let category: ErrorCategory
    public let count: Int
    /// Errors per 100 words corrected.
    public let rate: Double
    public let trend: ProgressTrend?
    public let series: [ProgressPoint]
    /// Most recent first, at most `ProgressReport.maximumExamples`.
    public let examples: [Mistake]
}

/// Recurring mistakes in one language over one period (#78), from History's
/// corrections. Pure: the window only shows it.
///
/// Loops over named functions rather than closures, and no condition in a
/// block nested inside another: muter drops mutants in closures, and places
/// none in a nested block once its function has one, and reports both as
/// survivors.
public struct ProgressReport: Sendable, Equatable {

    /// Below this many words in a period, a rate is not called reliable and
    /// no trend is shown.
    public static let minimumWords = 300
    /// A trend is a change of at least this share of the earlier rate...
    public static let trendShare = 0.2
    /// ...and at least this much per 100 words.
    public static let trendMinimum = 0.1
    public static let maximumExamples = 20
    /// Rates are fractions: 0.8 - 1.0 is -0.19999..., which must still
    /// count as the 20 % it is.
    static let tolerance = 1e-9

    public let language: LanguageCode
    public let period: ProgressPeriod
    public let words: Int
    public let errors: Int
    /// Nil when nothing was corrected.
    public let rate: Double?
    public let isReliable: Bool
    public let trend: ProgressTrend?
    public let rows: [ProgressRow]

    public init(
        corrections: [CorrectionStats], language: LanguageCode, period: ProgressPeriod, now: Date
    ) {
        let length = TimeInterval(period.days) * 86_400
        let start = now.addingTimeInterval(-length)
        let previousStart = start.addingTimeInterval(-length)
        let current = Self.select(corrections, language, from: start, to: now)
        let previous = Self.select(corrections, language, from: previousStart, to: start)
        let words = Self.words(current)
        let previousWords = Self.words(previous)
        let errors = Self.errors(current)

        self.language = language
        self.period = period
        self.words = words
        self.errors = errors
        self.rate = Self.rate(errors, words)
        self.isReliable = words >= Self.minimumWords
        var trend: ProgressTrend?
        if isReliable { trend = Self.trend(errors, words, Self.errors(previous), previousWords) }
        self.trend = trend

        var rows: [ProgressRow] = []
        let window = Window(
            current: current, previous: previous, words: words, previousWords: previousWords,
            start: start, period: period, isReliable: isReliable)
        for category in ErrorCategory.allCases {
            if let row = Self.row(category, window) { rows.append(row) }
        }
        self.rows = rows.sorted(by: Self.precedes)
    }

    /// What every row is computed from.
    struct Window {
        let current: [CorrectionStats]
        let previous: [CorrectionStats]
        let words: Int
        let previousWords: Int
        let start: Date
        let period: ProgressPeriod
        let isReliable: Bool
    }

    /// The category's row; nil when it had no error in the period.
    static func row(_ category: ErrorCategory, _ window: Window) -> ProgressRow? {
        let count = count(category, in: window.current)
        guard count > 0 else { return nil }
        return ProgressRow(
            category: category, count: count, rate: rate(count, window.words) ?? 0,
            trend: rowTrend(category, count, window),
            series: series(category, window.current, start: window.start, period: window.period),
            examples: examples(category, window.current))
    }

    static func rowTrend(_ category: ErrorCategory, _ count: Int, _ window: Window) -> ProgressTrend? {
        guard window.isReliable else { return nil }
        return trend(count, window.words, Self.count(category, in: window.previous), window.previousWords)
    }

    /// The languages with corrections, the most words first. One entry
    /// per base code, as the report matches them: "de" and "de-ch" are one
    /// language, under the code seen first.
    public static func languages(in corrections: [CorrectionStats]) -> [LanguageCode] {
        var totals: [LanguageCode: Int] = [:]
        var named: [LanguageCode: LanguageCode] = [:]
        for correction in corrections {
            let base = correction.language.baseSubtag
            let code = named[base] ?? correction.language
            named[base] = code
            totals[code, default: 0] += correction.wordCount
        }
        var ranked: [(LanguageCode, Int)] = []
        for entry in totals { ranked.append((entry.key, entry.value)) }
        return ranked.sorted(by: moreWords).map(\.0)
    }

    static func moreWords(_ lhs: (LanguageCode, Int), _ rhs: (LanguageCode, Int)) -> Bool {
        if lhs.1 > rhs.1 { return true }
        if lhs.1 < rhs.1 { return false }
        return lhs.0.rawValue < rhs.0.rawValue
    }

    /// The trend from the earlier counts to these: nil when the earlier
    /// period had too few words to compare with.
    static func trend(_ count: Int, _ words: Int, _ earlierCount: Int, _ earlierWords: Int) -> ProgressTrend? {
        if earlierWords < minimumWords { return nil }
        let now = rate(count, words) ?? 0
        let before = rate(earlierCount, earlierWords) ?? 0
        let change = now - before
        let size = abs(change) + tolerance
        if size < trendMinimum { return .steady }
        if size < trendShare * before { return .steady }
        if change < 0 { return .down(from: before) }
        return .up(from: before)
    }

    /// Per 100 words; nil for no words.
    static func rate(_ count: Int, _ words: Int) -> Double? {
        if words <= 0 { return nil }
        return Double(count) * 100 / Double(words)
    }

    /// In `language` (by base code: "de" finds "de-ch"), from `start` up
    /// to, not including, `end`.
    static func select(
        _ corrections: [CorrectionStats], _ language: LanguageCode, from start: Date, to end: Date
    ) -> [CorrectionStats] {
        var found: [CorrectionStats] = []
        for correction in corrections where isIn(correction, language, start, end) {
            found.append(correction)
        }
        return found
    }

    static func isIn(_ correction: CorrectionStats, _ language: LanguageCode, _ start: Date, _ end: Date) -> Bool {
        if correction.language.baseSubtag != language.baseSubtag { return false }
        if correction.date < start { return false }
        return correction.date < end
    }

    static func words(_ corrections: [CorrectionStats]) -> Int {
        var total = 0
        for correction in corrections { total += correction.wordCount }
        return total
    }

    static func errors(_ corrections: [CorrectionStats]) -> Int {
        var total = 0
        for correction in corrections { total += correction.mistakes.count }
        return total
    }

    static func count(_ category: ErrorCategory, in corrections: [CorrectionStats]) -> Int {
        var total = 0
        for correction in corrections { total += mistakes(category, in: correction).count }
        return total
    }

    /// One point per day or week from `start`, so a "day" runs from this
    /// time of day to the next, not midnight to midnight. The last week of
    /// 30 or 90 days is shorter (2 or 6 days), so its rate is noisier.
    static func series(
        _ category: ErrorCategory, _ corrections: [CorrectionStats], start: Date, period: ProgressPeriod
    ) -> [ProgressPoint] {
        let bucket = TimeInterval(period.bucketDays) * 86_400
        let buckets = (period.days + period.bucketDays - 1) / period.bucketDays
        var words = [Int](repeating: 0, count: buckets)
        var counts = [Int](repeating: 0, count: buckets)
        for correction in corrections {
            let index = min(Int(correction.date.timeIntervalSince(start) / bucket), buckets - 1)
            words[index] += correction.wordCount
            for mistake in correction.mistakes where mistake.category == category { counts[index] += 1 }
        }
        var points: [ProgressPoint] = []
        for index in 0..<buckets {
            points.append(ProgressPoint(
                start: start.addingTimeInterval(TimeInterval(index) * bucket),
                rate: rate(counts[index], words[index])))
        }
        return points
    }

    /// The category's mistakes, the most recent correction first.
    static func examples(_ category: ErrorCategory, _ corrections: [CorrectionStats]) -> [Mistake] {
        var found: [Mistake] = []
        for correction in corrections.reversed() {
            found += mistakes(category, in: correction)
        }
        return Array(found.prefix(maximumExamples))
    }

    static func mistakes(_ category: ErrorCategory, in correction: CorrectionStats) -> [Mistake] {
        var found: [Mistake] = []
        for mistake in correction.mistakes where mistake.category == category {
            found.append(mistake)
        }
        return found
    }

    /// More errors first; ties in the categories' own order.
    static func precedes(_ lhs: ProgressRow, _ rhs: ProgressRow) -> Bool {
        if lhs.count > rhs.count { return true }
        if lhs.count < rhs.count { return false }
        return order(lhs.category) < order(rhs.category)
    }

    static func order(_ category: ErrorCategory) -> Int {
        ErrorCategory.allCases.firstIndex(of: category) ?? 0
    }
}
