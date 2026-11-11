import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Learning rules: what counts, the week, the streak and the popup line (#136)")
struct LearningRulesTests {

    private typealias Fixtures = LearningFixtures
    private let monday = LearningFixtures.date(2026, 11, 9)

    /// A log that already has "First steps", so a line is about the day.
    private func seasoned(_ days: [LearningDay]) -> LearningLog {
        var log = Fixtures.log(days)
        log.earn(.firstSteps, on: LearningDay(number: 20_260_101))
        return log
    }

    private func outcome(
        _ record: HistoryRecord, _ log: LearningLog, goal: Int = 3, corrections: [CorrectionStats] = []
    ) -> LearningOutcome? {
        LearningRules.outcome(of: record, log: log, context: Fixtures.context(goal: goal, corrections: corrections))
    }

    // MARK: - What counts

    @Test("a Correct of ten words or more in a language that is not mine counts")
    func correctCounts() {
        #expect(LearningRules.isLearning(Fixtures.correct(monday, words: 10), myLanguage: Fixtures.english))
        #expect(!LearningRules.isLearning(Fixtures.correct(monday, words: 9), myLanguage: Fixtures.english))
        #expect(!LearningRules.isLearning(.sample(action: .correct), myLanguage: Fixtures.english))
    }

    @Test("my own language never counts, matched by base code")
    func mineDoesNotCount() {
        let british = Fixtures.correct(monday, words: 50, language: LanguageCode("en-gb"))
        #expect(!LearningRules.isLearning(british, myLanguage: Fixtures.english))
        #expect(!LearningRules.isLearning(Fixtures.correct(monday, words: 50), myLanguage: LanguageCode("de")))
        #expect(!LearningRules.isLearning(Fixtures.explain(monday), myLanguage: LanguageCode("de")))
    }

    @Test("an Explain counts; Translate and Re-pitch never do")
    func otherActions() {
        #expect(LearningRules.isLearning(Fixtures.explain(monday), myLanguage: Fixtures.english))
        #expect(!LearningRules.isLearning(.sample(action: .translate), myLanguage: Fixtures.english))
        #expect(!LearningRules.isLearning(.sample(action: .repitch), myLanguage: Fixtures.english))
        #expect(outcome(.sample(action: .translate), LearningLog()) == nil)
    }

    // MARK: - The outcome

    @Test("the first learning action starts the log and earns First steps")
    func first() throws {
        let result = try #require(outcome(Fixtures.correct(monday, words: 20), LearningLog()))
        #expect(result.log.days == [Fixtures.day(2026, 11, 9)])
        #expect(result.log.wordsCorrected == 20)
        #expect(result.log.explanations == 0)
        #expect(result.earned == [.firstSteps])
        #expect(result.log.earned == [EarnedMilestone(milestone: .firstSteps, day: Fixtures.day(2026, 11, 9))])
        #expect(result.line == "Milestone: First steps")
    }

    @Test("an Explain adds an explanation, not words")
    func explainTotals() throws {
        let result = try #require(outcome(Fixtures.explain(monday), seasoned([])))
        #expect(result.log.explanations == 1)
        #expect(result.log.wordsCorrected == 0)
        #expect(result.line == "Learning day 1 of 3 this week")
    }

    @Test("a second action the same day adds to the totals and says nothing")
    func sameDay() throws {
        let log = seasoned([Fixtures.day(2026, 11, 9)])
        let result = try #require(outcome(Fixtures.correct(monday, words: 15), log))
        #expect(result.log.days.count == 1)
        #expect(result.log.wordsCorrected == 15)
        #expect(result.earned.isEmpty)
        #expect(result.line == nil)
    }

    @Test("the first action of another day names the day of the week's goal")
    func newDay() throws {
        let log = seasoned([Fixtures.day(2026, 11, 9)])
        let result = try #require(outcome(Fixtures.correct(Fixtures.date(2026, 11, 10)), log))
        #expect(result.line == "Learning day 2 of 3 this week")
    }

    @Test("the day that meets the goal says so, with the streak from two weeks on")
    func goalMet() throws {
        let two = [Fixtures.day(2026, 11, 9), Fixtures.day(2026, 11, 10)]
        let wednesday = Fixtures.correct(Fixtures.date(2026, 11, 11))
        #expect(try #require(outcome(wednesday, seasoned(two))).line == "Weekly goal met")
        let lastWeek = [Fixtures.day(2026, 11, 2), Fixtures.day(2026, 11, 3), Fixtures.day(2026, 11, 6)]
        #expect(try #require(outcome(wednesday, seasoned(lastWeek + two))).line
            == "Weekly goal met \u{00B7} 2 weeks in a row")
    }

    @Test("a day beyond the goal is just counted")
    func beyondGoal() throws {
        let three = [Fixtures.day(2026, 11, 9), Fixtures.day(2026, 11, 10), Fixtures.day(2026, 11, 11)]
        let result = try #require(outcome(Fixtures.explain(Fixtures.date(2026, 11, 12)), seasoned(three)))
        #expect(result.line == "Learning day 4 this week")
    }

    @Test("a milestone comes before the day, and several share the line")
    func milestoneFirst() throws {
        var log = seasoned([])
        log.addWords(995)
        let result = try #require(outcome(Fixtures.correct(monday, words: 120, []), log))
        #expect(result.earned == [.words(1_000), .cleanText])
        #expect(result.line == "Milestones: 1,000 words, Clean text")
    }

    @Test("the lines, one by one")
    func lines() {
        let languages = LanguageConfig.shippedDefaults
        let running = LearningWeek(days: 2, goal: 3, streak: 0)
        let met = LearningWeek(days: 3, goal: 3, streak: 1)
        let over = LearningWeek(days: 4, goal: 3, streak: 5)
        #expect(LearningRules.line([], before: running, after: running, isNewDay: false, languages: languages) == nil)
        #expect(LearningRules.line([], before: running, after: met, isNewDay: true, languages: languages)
            == "Weekly goal met")
        #expect(LearningRules.line([], before: met, after: over, isNewDay: true, languages: languages)
            == "Learning day 4 this week")
        #expect(LearningRules.line([], before: met, after: met, isNewDay: false, languages: languages) == nil)
        #expect(LearningRules.line([.cleanText], before: met, after: met, isNewDay: false, languages: languages)
            == "Milestone: Clean text")
        #expect(LearningRules.goalLine(LearningWeek(days: 3, goal: 3, streak: 2))
            == "Weekly goal met \u{00B7} 2 weeks in a row")
        #expect(LearningRules.dayLine(LearningWeek(days: 3, goal: 3, streak: 0)) == "Learning day 3 of 3 this week")
    }

    // MARK: - The week and the streak

    @Test("only this calendar week's days count towards the goal")
    func weekDays() {
        let log = Fixtures.log([Fixtures.day(2026, 11, 8), Fixtures.day(2026, 11, 9), Fixtures.day(2026, 11, 11)])
        let week = LearningRules.week(log, goal: 3, now: Fixtures.date(2026, 11, 12), calendar: Fixtures.calendar)
        #expect(week == LearningWeek(days: 2, goal: 3, streak: 0))
        #expect(!week.isMet)
        #expect(LearningWeek(days: 3, goal: 3, streak: 0).isMet)
    }

    @Test("the week starts where the calendar says")
    func sundayFirst() {
        var sunday = Fixtures.calendar
        sunday.firstWeekday = 1
        let log = Fixtures.log([Fixtures.day(2026, 11, 8), Fixtures.day(2026, 11, 9)])
        #expect(LearningRules.week(log, goal: 3, now: monday, calendar: sunday).days == 2)
        #expect(LearningRules.week(log, goal: 3, now: monday, calendar: Fixtures.calendar).days == 1)
    }

    @Test("a week runs across the year's end")
    func yearEnd() {
        let log = Fixtures.log([Fixtures.day(2026, 12, 28), Fixtures.day(2026, 12, 31), Fixtures.day(2027, 1, 1)])
        let week = LearningRules.week(log, goal: 3, now: Fixtures.date(2027, 1, 2), calendar: Fixtures.calendar)
        #expect(week.days == 3)
        #expect(week.streak == 1)
    }

    private let fullWeeks = [
        LearningFixtures.day(2026, 10, 26), LearningFixtures.day(2026, 10, 27), LearningFixtures.day(2026, 10, 30),
        LearningFixtures.day(2026, 11, 2), LearningFixtures.day(2026, 11, 4), LearningFixtures.day(2026, 11, 8),
    ]

    private func streak(_ days: [LearningDay], goal: Int = 3, now: Date? = nil) -> Int {
        LearningRules.week(
            Fixtures.log(days), goal: goal, now: now ?? Fixtures.date(2026, 11, 13), calendar: Fixtures.calendar
        ).streak
    }

    @Test("the streak counts this week once it is met")
    func streakWithThisWeek() {
        let thisWeek = [Fixtures.day(2026, 11, 9), Fixtures.day(2026, 11, 10), Fixtures.day(2026, 11, 12)]
        #expect(streak(fullWeeks + thisWeek) == 3)
        #expect(streak(thisWeek) == 1)
    }

    @Test("a week still running does not break the streak")
    func streakWhileRunning() {
        #expect(streak(fullWeeks + [Fixtures.day(2026, 11, 9)]) == 2)
        #expect(streak(fullWeeks) == 2)
    }

    @Test("a week that missed the goal ends the streak")
    func streakGap() {
        let gap = [
            Fixtures.day(2026, 10, 26), Fixtures.day(2026, 10, 27), Fixtures.day(2026, 10, 30),
            Fixtures.day(2026, 11, 2), Fixtures.day(2026, 11, 4),
        ]
        #expect(streak(gap) == 0)
        #expect(streak(gap + [Fixtures.day(2026, 11, 9), Fixtures.day(2026, 11, 10), Fixtures.day(2026, 11, 12)]) == 1)
        #expect(streak([]) == 0)
    }

    @Test("the weeks are judged against the goal as it is now")
    func streakFollowsGoal() {
        let gap = [
            Fixtures.day(2026, 10, 26), Fixtures.day(2026, 10, 27), Fixtures.day(2026, 10, 30),
            Fixtures.day(2026, 11, 2), Fixtures.day(2026, 11, 4),
        ]
        #expect(streak(gap, goal: 2) == 2)
        #expect(streak(gap, goal: 4) == 0)
    }

    @Test("a goal below one is one")
    func goalFloor() {
        let week = LearningRules.week(
            Fixtures.log([Fixtures.day(2026, 11, 3)]), goal: 0, now: monday, calendar: Fixtures.calendar)
        #expect(week == LearningWeek(days: 0, goal: 1, streak: 1))
    }

    @Test("a long streak is counted week by week")
    func longStreak() {
        var days: [LearningDay] = []
        for week in 1...20 {
            let start = Fixtures.date(2026, 11, 9).addingTimeInterval(-Double(week) * 7 * 86_400)
            days.append(LearningDay(start, calendar: Fixtures.calendar))
        }
        #expect(streak(days, goal: 1, now: monday) == 20)
    }

    // MARK: - Milestones

    @Test("word milestones at 1,000, 5,000 and 10,000 words corrected")
    func wordMilestones() throws {
        var log = seasoned([Fixtures.day(2026, 11, 9)])
        log.addWords(989)
        #expect(try #require(outcome(Fixtures.correct(monday, words: 10), log)).earned.isEmpty)
        #expect(try #require(outcome(Fixtures.correct(monday, words: 11), log)).earned == [.words(1_000)])
        #expect(try #require(outcome(Fixtures.correct(monday, words: 4_011), log)).earned
            == [.words(1_000), .words(5_000)])
        log.addWords(9_000)
        log.earn(.words(1_000), on: Fixtures.day(2026, 11, 9))
        log.earn(.words(5_000), on: Fixtures.day(2026, 11, 9))
        #expect(try #require(outcome(Fixtures.correct(monday, words: 11), log)).earned == [.words(10_000)])
    }

    @Test("explanation milestones at 10 and 50")
    func explanationMilestones() throws {
        var log = seasoned([Fixtures.day(2026, 11, 9)])
        for _ in 0..<8 { log.addExplanation() }
        #expect(try #require(outcome(Fixtures.explain(monday), log)).earned.isEmpty)
        log.addExplanation()
        #expect(try #require(outcome(Fixtures.explain(monday), log)).earned == [.explanations(10)])
        // A Correct does not move it.
        #expect(try #require(outcome(Fixtures.correct(monday), log)).earned.isEmpty)
    }

    @Test("Clean text: a correction of 100 words or more with no errors")
    func cleanText() throws {
        let log = seasoned([Fixtures.day(2026, 11, 9)])
        #expect(try #require(outcome(Fixtures.correct(monday, words: 100, []), log)).earned == [.cleanText])
        #expect(try #require(outcome(Fixtures.correct(monday, words: 99, []), log)).earned.isEmpty)
        #expect(try #require(outcome(Fixtures.correct(monday, words: 100, [.spelling]), log)).earned.isEmpty)
        // Changed with no error listed: the popup warns, so not clean.
        #expect(try #require(outcome(Fixtures.correct(monday, words: 100, [], result: "y"), log)).earned.isEmpty)
        #expect(!LearningRules.isClean(Fixtures.explain(monday)))
        #expect(!LearningRules.isClean(.sample(action: .correct)))
    }

    @Test("a milestone already earned is not earned again")
    func once() throws {
        var log = seasoned([Fixtures.day(2026, 11, 9)])
        log.earn(.cleanText, on: Fixtures.day(2026, 11, 9))
        let result = try #require(outcome(Fixtures.correct(monday, words: 100, []), log))
        #expect(result.earned.isEmpty)
        #expect(result.log.earned.count == 2)
    }

    @Test("a tamed category is earned once per language, whatever its region")
    func tamedOnce() throws {
        var log = seasoned([Fixtures.day(2026, 11, 9)])
        log.earn(.tamed(.grammaticalCase, LanguageCode("de")), on: Fixtures.day(2026, 11, 1))
        let corrections = [stats(daysBefore: 40, words: 400, cases(6)), stats(daysBefore: 2, words: 400, cases(2))]
        let result = try #require(outcome(Fixtures.correct(monday), log, corrections: corrections))
        #expect(result.earned.isEmpty)
        #expect(result.line == nil)
    }

    @Test("the streak holds across a change of clocks and the year's end, in a real time zone")
    func streakInZurich() {
        var zurich = Fixtures.calendar
        zurich.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .gmt
        // Mondays from 2026-10-12 to 2027-04-05: both clock changes and New Year.
        var days: [LearningDay] = []
        for week in 0..<26 {
            days.append(LearningDay(
                Fixtures.date(2026, 10, 12).addingTimeInterval(Double(week) * 7 * 86_400), calendar: zurich))
        }
        let week = LearningRules.week(
            Fixtures.log(days), goal: 1, now: Fixtures.date(2027, 4, 7), calendar: zurich)
        #expect(week == LearningWeek(days: 1, goal: 1, streak: 26))
        let sunday = LearningRules.week(
            Fixtures.log(days), goal: 1, now: Fixtures.date(2027, 1, 3), calendar: zurich)
        #expect(sunday.streak == 12)
    }

    @Test("streak milestones at 4 and 12 weeks")
    func streakMilestones() throws {
        var days: [LearningDay] = []
        for week in 1...3 {
            let start = monday.addingTimeInterval(-Double(week) * 7 * 86_400)
            days.append(LearningDay(start, calendar: Fixtures.calendar))
        }
        let three = try #require(outcome(Fixtures.explain(monday), seasoned(days), goal: 1))
        #expect(three.earned == [.streak(4)])
        #expect(three.line == "Milestone: 4 weeks in a row")
        let two = try #require(outcome(Fixtures.explain(monday), seasoned(Array(days.prefix(2))), goal: 1))
        #expect(two.earned.isEmpty)
        for week in 4...11 {
            let start = monday.addingTimeInterval(-Double(week) * 7 * 86_400)
            days.append(LearningDay(start, calendar: Fixtures.calendar))
        }
        let twelve = try #require(outcome(Fixtures.explain(monday), seasoned(days), goal: 1))
        #expect(twelve.earned == [.streak(4), .streak(12)])
    }

    // MARK: - Tamed

    private func stats(
        daysBefore: Double, words: Int, _ categories: [ErrorCategory], language: LanguageCode? = nil
    ) -> CorrectionStats {
        CorrectionStats(
            date: monday.addingTimeInterval(-daysBefore * 86_400), language: language ?? Fixtures.german,
            wordCount: words, mistakes: categories.map { Mistake.sample($0) })
    }

    private func cases(_ count: Int) -> [ErrorCategory] {
        [ErrorCategory](repeating: .grammaticalCase, count: count)
    }

    private func tamed(_ corrections: [CorrectionStats]) -> [ErrorCategory] {
        LearningRules.tamed(by: Fixtures.correct(monday), corrections)
    }

    @Test("a category is tamed when its rate at least halved against the 30 days before")
    func tamedWhenHalved() throws {
        let earlier = stats(daysBefore: 40, words: 400, cases(6))
        #expect(tamed([earlier, stats(daysBefore: 2, words: 400, cases(2))]) == [.grammaticalCase])
        #expect(tamed([earlier, stats(daysBefore: 2, words: 400, cases(3))]) == [.grammaticalCase])
        #expect(tamed([earlier, stats(daysBefore: 2, words: 400, cases(4))]).isEmpty)
        #expect(tamed([earlier, stats(daysBefore: 2, words: 400, [])]) == [.grammaticalCase])
        let result = try #require(outcome(
            Fixtures.correct(monday), seasoned([Fixtures.day(2026, 11, 9)]),
            corrections: [earlier, stats(daysBefore: 2, words: 400, cases(2))]))
        #expect(result.earned == [.tamed(.grammaticalCase, LanguageCode("de"))])
        #expect(result.line?.hasPrefix("Milestone: Case tamed in ") == true)
    }

    @Test("it takes five errors of the category in the earlier 30 days")
    func tamedNeedsEnoughBefore() {
        #expect(tamed([stats(daysBefore: 40, words: 400, cases(4)), stats(daysBefore: 2, words: 400, [])]).isEmpty)
        #expect(tamed([stats(daysBefore: 40, words: 400, cases(5)), stats(daysBefore: 2, words: 400, [])])
            == [.grammaticalCase])
    }

    @Test("it takes 300 words in both periods")
    func tamedNeedsWords() {
        #expect(tamed([stats(daysBefore: 40, words: 400, cases(6)), stats(daysBefore: 2, words: 299, [])]).isEmpty)
        #expect(tamed([stats(daysBefore: 40, words: 400, cases(6)), stats(daysBefore: 2, words: 300, [])])
            == [.grammaticalCase])
        #expect(tamed([stats(daysBefore: 40, words: 299, cases(6)), stats(daysBefore: 2, words: 400, [])]).isEmpty)
    }

    @Test("a fall too small for Progress to call a trend is not tamed")
    func tamedNeedsATrend() {
        let earlier = stats(daysBefore: 40, words: 10_000, cases(5))
        #expect(tamed([earlier, stats(daysBefore: 2, words: 400, [])]).isEmpty)
    }

    @Test("the periods are 30 days each, the record's own moment in the later one")
    func tamedPeriods() {
        let earlier = stats(daysBefore: 31, words: 400, cases(6))
        #expect(tamed([earlier, stats(daysBefore: 0, words: 400, [])]) == [.grammaticalCase])
        // Both in the later period: nothing to compare with.
        #expect(tamed([stats(daysBefore: 29, words: 400, cases(6)), stats(daysBefore: 0, words: 400, [])]).isEmpty)
        // Older than 60 days: not the period before.
        #expect(tamed([stats(daysBefore: 61, words: 400, cases(6)), stats(daysBefore: 2, words: 400, [])]).isEmpty)
    }

    @Test("only the record's language, and only for a Correct")
    func tamedLanguage() {
        let french = LanguageCode("fr")
        let corrections = [
            stats(daysBefore: 40, words: 400, cases(6), language: french),
            stats(daysBefore: 2, words: 400, [], language: french),
        ]
        #expect(tamed(corrections).isEmpty)
        #expect(LearningRules.tamed(by: Fixtures.correct(monday, language: french), corrections) == [.grammaticalCase])
        #expect(LearningRules.tamed(by: Fixtures.explain(monday, language: french), corrections).isEmpty)
    }

    @Test("each category on its own")
    func tamedPerCategory() {
        let earlier = stats(daysBefore: 40, words: 400, cases(6) + [ErrorCategory](repeating: .gender, count: 6))
        let later = stats(daysBefore: 2, words: 400, cases(1) + [ErrorCategory](repeating: .gender, count: 5))
        #expect(tamed([earlier, later]) == [.grammaticalCase])
    }

    // MARK: - Next

    @Test("Next is the count milestone furthest along")
    func next() {
        #expect(LearningRules.next(LearningLog()) == NextMilestone(milestone: .words(1_000), current: 0, target: 1_000))
        var log = LearningLog()
        log.addWords(500)
        for _ in 0..<5 { log.addExplanation() }
        #expect(LearningRules.next(log) == NextMilestone(milestone: .words(1_000), current: 500, target: 1_000))
        log.addExplanation()
        #expect(LearningRules.next(log) == NextMilestone(milestone: .explanations(10), current: 6, target: 10))
        log.addWords(500)
        #expect(LearningRules.next(log) == NextMilestone(milestone: .explanations(10), current: 6, target: 10))
        log.addWords(3_000)
        #expect(LearningRules.next(log) == NextMilestone(milestone: .words(5_000), current: 4_000, target: 5_000))
    }

    @Test("Next when one kind, or both, are all earned")
    func nextAtTheEnd() {
        var words = LearningLog()
        words.addWords(10_000)
        words.addExplanation()
        #expect(LearningRules.next(words) == NextMilestone(milestone: .explanations(10), current: 1, target: 10))
        var explanations = LearningLog()
        for _ in 0..<50 { explanations.addExplanation() }
        #expect(LearningRules.next(explanations) == NextMilestone(milestone: .words(1_000), current: 0, target: 1_000))
        for _ in 0..<50 { words.addExplanation() }
        #expect(LearningRules.next(words) == nil)
        #expect(LearningRules.next([10, 50], 10) == 50)
        #expect(LearningRules.next([10, 50], 9) == 10)
        #expect(LearningRules.next([10, 50], 50) == nil)
    }
}
