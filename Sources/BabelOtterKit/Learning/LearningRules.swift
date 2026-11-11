import Foundation

/// This calendar week against the goal, and the weeks in a row before it.
public struct LearningWeek: Sendable, Equatable {
    /// Learning days so far this week.
    public let days: Int
    public let goal: Int
    /// Weeks in a row with the goal met: counted from this week once it is
    /// met, else from last week, so a week still running never breaks it.
    public let streak: Int

    public var isMet: Bool { days >= goal }
}

/// What the rules need beside the record and the log.
public struct LearningContext: Sendable {
    public let goal: Int
    public let myLanguage: LanguageCode
    public let languages: [LanguageConfig]
    public let calendar: Calendar
    /// History's corrections of the last 60 days or more, the record's own
    /// among them: what "tamed" is judged from.
    public let corrections: [CorrectionStats]

    public init(
        goal: Int, myLanguage: LanguageCode, languages: [LanguageConfig], calendar: Calendar,
        corrections: [CorrectionStats]
    ) {
        self.goal = goal
        self.myLanguage = myLanguage
        self.languages = languages
        self.calendar = calendar
        self.corrections = corrections
    }
}

/// What a learning action did: the log after it, the milestones it newly
/// earned, and the popup's one line (nil when nothing moved).
public struct LearningOutcome: Sendable, Equatable {
    public let log: LearningLog
    public let earned: [Milestone]
    public let line: String?
}

/// The count milestone closest to being earned, for Progress's "Next:".
public struct NextMilestone: Sendable, Equatable {
    public let milestone: Milestone
    public let current: Int
    public let target: Int
}

/// The learning goal's rules (#136): what counts, the week and the streak,
/// the milestones, and the popup's line. Pure: the app stores the log and
/// shows the line.
public enum LearningRules {

    /// A Correct of fewer words is not a learning action.
    public static let minimumWords = 10
    /// "Clean text" takes a correction of at least this many words.
    public static let cleanTextWords = 100
    /// "Tamed" compares this many days with as many before them...
    public static let tamedDays = 30
    /// ...and needs this many errors of the category in the earlier ones.
    public static let tamedMinimumBefore = 5
    /// Weeks looked back for the streak: more than the log can hold.
    static let maximumWeeks = 400

    /// A Correct of `minimumWords` or more, or an Explain, of a text that
    /// is not in my language.
    public static func isLearning(_ record: HistoryRecord, myLanguage: LanguageCode) -> Bool {
        if record.sourceLanguage.baseSubtag == myLanguage.baseSubtag { return false }
        switch record.action {
        case .explain:
            return true
        case .correct:
            return (record.wordCount ?? 0) >= minimumWords
        case .translate, .repitch:
            return false
        }
    }

    /// The log after `record`, and what it earned; nil when the record is
    /// not a learning action. The day is the record's own.
    public static func outcome(
        of record: HistoryRecord, log: LearningLog, context: LearningContext
    ) -> LearningOutcome? {
        if !isLearning(record, myLanguage: context.myLanguage) { return nil }
        let day = LearningDay(record.date, calendar: context.calendar)
        let before = week(log, goal: context.goal, now: record.date, calendar: context.calendar)
        let isNewDay = !log.has(day)
        var next = log
        next.add(day)
        count(record, in: &next)
        let after = week(next, goal: context.goal, now: record.date, calendar: context.calendar)
        let earned = earned(by: record, log: next, streak: after.streak, corrections: context.corrections)
        for milestone in earned { next.earn(milestone, on: day) }
        return LearningOutcome(
            log: next, earned: earned,
            line: line(earned, before: before, after: after, isNewDay: isNewDay, languages: context.languages))
    }

    static func count(_ record: HistoryRecord, in log: inout LearningLog) {
        if case .explain = record.action {
            log.addExplanation()
            return
        }
        log.addWords(record.wordCount ?? 0)
    }

    // MARK: - The week and the streak

    public static func week(_ log: LearningLog, goal: Int, now: Date, calendar: Calendar) -> LearningWeek {
        let goal = max(goal, 1)
        guard let this = weekStart(now, calendar) else { return LearningWeek(days: 0, goal: goal, streak: 0) }
        let counts = daysByWeek(log, calendar)
        let days = counts[this] ?? 0
        var streak = 0
        if days >= goal { streak = 1 }
        var cursor = this
        for _ in 0..<maximumWeeks {
            guard let earlier = weekBefore(cursor, calendar) else { break }
            if (counts[earlier] ?? 0) < goal { break }
            streak += 1
            cursor = earlier
        }
        return LearningWeek(days: days, goal: goal, streak: streak)
    }

    static func weekStart(_ date: Date, _ calendar: Calendar) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }

    /// The start of the week before the one starting at `start`: found
    /// from a moment inside it, so a change of clocks cannot miss it.
    static func weekBefore(_ start: Date, _ calendar: Calendar) -> Date? {
        guard let inside = calendar.date(byAdding: .day, value: -3, to: start) else { return nil }
        return weekStart(inside, calendar)
    }

    /// Learning days per week, by the week's start.
    static func daysByWeek(_ log: LearningLog, _ calendar: Calendar) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for day in log.days {
            if let start = start(ofWeekWith: day, calendar) { counts[start, default: 0] += 1 }
        }
        return counts
    }

    static func start(ofWeekWith day: LearningDay, _ calendar: Calendar) -> Date? {
        guard let date = day.date(calendar: calendar) else { return nil }
        return weekStart(date, calendar)
    }

    // MARK: - Milestones

    /// The milestones `record` newly earns, given the log already counting
    /// it and the streak after it.
    static func earned(
        by record: HistoryRecord, log: LearningLog, streak: Int, corrections: [CorrectionStats]
    ) -> [Milestone] {
        var candidates: [Milestone] = [.firstSteps]
        for step in Milestone.wordSteps where log.wordsCorrected >= step {
            candidates.append(.words(step))
        }
        for step in Milestone.explanationSteps where log.explanations >= step {
            candidates.append(.explanations(step))
        }
        if isClean(record) { candidates.append(.cleanText) }
        for category in tamed(by: record, corrections) {
            candidates.append(.tamed(category, record.sourceLanguage.baseSubtag))
        }
        for step in Milestone.streakSteps where streak >= step {
            candidates.append(.streak(step))
        }
        var new: [Milestone] = []
        for candidate in candidates where !log.hasEarned(candidate) {
            new.append(candidate)
        }
        return new
    }

    /// A correction of `cleanTextWords` or more in which no error was
    /// found and the text came back as it was: a text changed with no error
    /// listed is one the popup warns about, not a clean one.
    static func isClean(_ record: HistoryRecord) -> Bool {
        guard case .correct = record.action else { return false }
        if (record.wordCount ?? 0) < cleanTextWords { return false }
        if record.result != record.source { return false }
        return record.mistakes.isEmpty
    }

    /// The categories Progress would now show falling to half or less in
    /// the record's language: the 30 days up to the record against the 30
    /// before, both with enough words for a trend.
    static func tamed(by record: HistoryRecord, _ corrections: [CorrectionStats]) -> [ErrorCategory] {
        guard case .correct = record.action else { return [] }
        let length = TimeInterval(tamedDays) * 86_400
        // The record's own moment is inside the period.
        let end = record.date.addingTimeInterval(1)
        let start = end.addingTimeInterval(-length)
        let language = record.sourceLanguage
        let current = ProgressReport.select(corrections, language, from: start, to: end)
        let previous = ProgressReport.select(
            corrections, language, from: start.addingTimeInterval(-length), to: start)
        let words = ProgressReport.words(current)
        if words < ProgressReport.minimumWords { return [] }
        let previousWords = ProgressReport.words(previous)
        var found: [ErrorCategory] = []
        for category in ErrorCategory.allCases {
            let count = ProgressReport.count(category, in: current)
            let before = ProgressReport.count(category, in: previous)
            if isTamed(count, words, before, previousWords) { found.append(category) }
        }
        return found
    }

    static func isTamed(_ count: Int, _ words: Int, _ before: Int, _ previousWords: Int) -> Bool {
        if before < tamedMinimumBefore { return false }
        guard case .down(let from)? = ProgressReport.trend(count, words, before, previousWords) else {
            return false
        }
        let rate = ProgressReport.rate(count, words) ?? 0
        return rate * 2 <= from + ProgressReport.tolerance
    }

    /// The count milestone not yet earned that is furthest along; nil once
    /// all are earned.
    public static func next(_ log: LearningLog) -> NextMilestone? {
        let words = next(Milestone.wordSteps, log.wordsCorrected)
        let explanations = next(Milestone.explanationSteps, log.explanations)
        guard let words else {
            guard let explanations else { return nil }
            return NextMilestone(
                milestone: .explanations(explanations), current: log.explanations, target: explanations)
        }
        let wordsNext = NextMilestone(milestone: .words(words), current: log.wordsCorrected, target: words)
        guard let explanations else { return wordsNext }
        // Compared as fractions, without dividing.
        if log.explanations * words > log.wordsCorrected * explanations {
            return NextMilestone(
                milestone: .explanations(explanations), current: log.explanations, target: explanations)
        }
        return wordsNext
    }

    /// The first step above `total`.
    static func next(_ steps: [Int], _ total: Int) -> Int? {
        for step in steps where step > total {
            return step
        }
        return nil
    }

    // MARK: - The popup's line

    /// One line, the first that applies: a milestone, the goal just met,
    /// the first learning action of the day; else nothing.
    static func line(
        _ earned: [Milestone], before: LearningWeek, after: LearningWeek, isNewDay: Bool,
        languages: [LanguageConfig]
    ) -> String? {
        if !earned.isEmpty { return milestoneLine(earned, languages) }
        if !isNewDay { return nil }
        if before.isMet { return dayLine(after) }
        if after.isMet { return goalLine(after) }
        return dayLine(after)
    }

    static func milestoneLine(_ earned: [Milestone], _ languages: [LanguageConfig]) -> String {
        var titles: [String] = []
        for milestone in earned { titles.append(milestone.title(languages: languages)) }
        if titles.count == 1 { return "Milestone: " + titles[0] }
        return "Milestones: " + titles.joined(separator: ", ")
    }

    static func goalLine(_ week: LearningWeek) -> String {
        if week.streak < 2 { return "Weekly goal met" }
        return "Weekly goal met \u{00B7} \(week.streak) weeks in a row"
    }

    static func dayLine(_ week: LearningWeek) -> String {
        if week.days > week.goal { return "Learning day \(week.days) this week" }
        return "Learning day \(week.days) of \(week.goal) this week"
    }
}
