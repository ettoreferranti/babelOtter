import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Progress report: recurring mistakes per 100 words, with a trend (#78)")
struct ProgressReportTests {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let german = LanguageCode("de-ch")
    private let day: TimeInterval = 86_400

    private func correction(
        daysAgo: Double, words: Int, _ categories: [ErrorCategory] = [], language: LanguageCode? = nil
    ) -> CorrectionStats {
        CorrectionStats(
            date: now.addingTimeInterval(-daysAgo * day), language: language ?? german, wordCount: words,
            mistakes: categories.map { Mistake.sample($0) })
    }

    private func report(_ corrections: [CorrectionStats], _ period: ProgressPeriod = .month) -> ProgressReport {
        ProgressReport(corrections: corrections, language: german, period: period, now: now)
    }

    @Test("words, errors and the rate per 100 words in the period")
    func totals() {
        let result = report([
            correction(daysAgo: 1, words: 200, [.grammaticalCase, .grammaticalCase]),
            correction(daysAgo: 10, words: 200, [.gender]),
        ])
        #expect(result.words == 400)
        #expect(result.errors == 3)
        #expect(result.rate == 0.75)
        #expect(result.isReliable)
    }

    @Test("only the period counts: older corrections are the previous period")
    func period() {
        let result = report([
            correction(daysAgo: 29, words: 100, [.gender]),
            correction(daysAgo: 31, words: 100, [.gender, .gender]),
        ])
        #expect(result.words == 100)
        #expect(result.errors == 1)
        #expect(report([correction(daysAgo: 6, words: 10)], .week).words == 10)
        #expect(report([correction(daysAgo: 8, words: 10)], .week).words == 0)
    }

    @Test("only the chosen language, matched by base code")
    func language() {
        let result = ProgressReport(
            corrections: [
                correction(daysAgo: 1, words: 50, language: LanguageCode("de")),
                correction(daysAgo: 1, words: 70, language: LanguageCode("fr")),
            ],
            language: german, period: .month, now: now)
        #expect(result.words == 50)
    }

    @Test("rows: one per category with errors, most frequent first, ties in category order")
    func rows() {
        let result = report([
            correction(daysAgo: 1, words: 400, [.spelling, .gender, .gender, .grammaticalCase, .preposition])
        ])
        #expect(result.rows.map(\.category) == [.gender, .grammaticalCase, .spelling, .preposition])
        #expect(result.rows.map(\.count) == [2, 1, 1, 1])
        #expect(result.rows[0].rate == 0.5)
    }

    @Test("under 300 words: not reliable, and no trend anywhere")
    func floor() {
        let previous = correction(daysAgo: 40, words: 1_000, [.gender])
        let thin = report([previous, correction(daysAgo: 1, words: 299, [.gender, .gender])])
        #expect(!thin.isReliable)
        #expect(thin.trend == nil)
        #expect(thin.rows.first?.trend == nil)
        let enough = report([previous, correction(daysAgo: 1, words: 300, [.gender, .gender])])
        #expect(enough.isReliable)
        #expect(enough.trend != nil)
    }

    @Test("no trend when the previous period had under 300 words")
    func noPrevious() {
        let result = report([
            correction(daysAgo: 40, words: 299, [.gender]),
            correction(daysAgo: 1, words: 1_000, [.gender]),
        ])
        #expect(result.trend == nil)
        #expect(result.rows.first?.trend == nil)
    }

    @Test("down and up: a change of at least 20 % and at least 0.1 per 100 words")
    func trends() {
        // 2.0 before, 1.0 now.
        #expect(ProgressReport.trend(10, 1_000, 20, 1_000) == .down(from: 2.0))
        #expect(ProgressReport.trend(30, 1_000, 20, 1_000) == .up(from: 2.0))
        // From nothing: up.
        #expect(ProgressReport.trend(1, 1_000, 0, 1_000) == .up(from: 0))
    }

    @Test("smaller changes are steady", arguments: [
        // 2.0 to 1.7: 15 % -- under the share.
        (17, 20),
        // 0.3 to 0.25: over 20 %, but only 0.05 -- under the minimum.
        (25, 30),
        // Exactly the same.
        (20, 20),
    ])
    func steady(_ now: Int, _ before: Int) {
        #expect(ProgressReport.trend(now, 10_000, before, 10_000) == .steady)
    }

    @Test("exactly at the thresholds is a trend")
    func atThresholds() {
        // 1.0 to 0.8: exactly 20 % and exactly 0.2.
        #expect(ProgressReport.trend(8, 1_000, 10, 1_000) == .down(from: 1.0))
        // 0.5 to 0.4: exactly 0.1 and 20 %.
        #expect(ProgressReport.trend(4, 1_000, 5, 1_000) == .down(from: 0.5))
        #expect(ProgressReport.trend(10, 1_000, 10, 299) == nil)
        #expect(ProgressReport.trend(10, 1_000, 10, 300) != nil)
    }

    @Test("the summary trend and a row's trend, end to end")
    func endToEnd() {
        let result = report([
            correction(daysAgo: 40, words: 1_000, Array(repeating: .gender, count: 20)),
            correction(daysAgo: 5, words: 1_000, Array(repeating: .gender, count: 5)),
        ])
        #expect(result.trend == .down(from: 2.0))
        #expect(result.rows.first?.trend == .down(from: 2.0))
    }

    @Test("rates: nil without words")
    func rate() {
        #expect(ProgressReport.rate(3, 0) == nil)
        #expect(ProgressReport.rate(3, 300) == 1.0)
        #expect(report([]).rate == nil)
        #expect(report([]).rows.isEmpty)
    }

    @Test("the series: per week for a month, per day for a week, nil where nothing was corrected")
    func series() {
        let month = report([
            correction(daysAgo: 29.5, words: 100, [.gender]),
            correction(daysAgo: 0.5, words: 200, [.gender]),
        ])
        let points = try? #require(month.rows.first?.series)
        #expect(points?.count == 5)
        #expect(points?.first?.rate == 1.0)
        #expect(points?.last?.rate == 0.5)
        #expect(points?[2].rate == nil)
        #expect(points?.first?.start == now.addingTimeInterval(-30 * day))
        #expect(points?[1].start == now.addingTimeInterval(-23 * day))

        let week = report([correction(daysAgo: 0.5, words: 100, [.gender])], .week)
        #expect(week.rows.first?.series.count == 7)
        #expect(week.rows.first?.series.last?.rate == 1.0)
        #expect(ProgressReport(corrections: [], language: german, period: .quarter, now: now).period.days == 90)
    }

    @Test("a week's chart point counts that category only, against all the week's words")
    func seriesCategory() {
        let result = report([correction(daysAgo: 0.5, words: 100, [.gender, .spelling, .spelling])])
        let gender = result.rows.first { $0.category == .gender }
        #expect(gender?.series.last?.rate == 1.0)
    }

    @Test("examples: the most recent correction first, at most 20")
    func examples() {
        let older = CorrectionStats(
            date: now.addingTimeInterval(-3 * day), language: german, wordCount: 10,
            mistakes: [.sample(.gender, original: "old")])
        let newer = CorrectionStats(
            date: now.addingTimeInterval(-1 * day), language: german, wordCount: 10,
            mistakes: [.sample(.gender, original: "new 1"), .sample(.spelling), .sample(.gender, original: "new 2")])
        let result = report([older, newer])
        let row = result.rows.first { $0.category == .gender }
        #expect(row?.examples.map(\.original.value) == ["new 1", "new 2", "old"])

        let many = CorrectionStats(
            date: now.addingTimeInterval(-day), language: german, wordCount: 10,
            mistakes: Array(repeating: .sample(.gender), count: 25))
        #expect(report([many]).rows.first?.examples.count == ProgressReport.maximumExamples)
        #expect(ProgressReport.maximumExamples == 20)
    }

    @Test("the languages with corrections, the most words first")
    func languages() {
        let corrections = [
            correction(daysAgo: 1, words: 10, language: LanguageCode("fr")),
            correction(daysAgo: 1, words: 30, language: german),
            correction(daysAgo: 1, words: 15, language: LanguageCode("fr")),
            correction(daysAgo: 1, words: 40, language: LanguageCode("es")),
        ]
        // Not alphabetical: Spanish has the most words.
        #expect(ProgressReport.languages(in: corrections) == [LanguageCode("es"), german, LanguageCode("fr")])
        let tie = [
            correction(daysAgo: 1, words: 10, language: LanguageCode("it")),
            correction(daysAgo: 1, words: 10, language: LanguageCode("fr")),
        ]
        #expect(ProgressReport.languages(in: tie) == [LanguageCode("fr"), LanguageCode("it")])
        #expect(ProgressReport.languages(in: []).isEmpty)
        let sameBase = [
            correction(daysAgo: 1, words: 10, language: LanguageCode("de")),
            correction(daysAgo: 1, words: 10, language: german),
            correction(daysAgo: 1, words: 15, language: LanguageCode("fr")),
        ]
        #expect(ProgressReport.languages(in: sameBase) == [LanguageCode("de"), LanguageCode("fr")])
    }

    @Test("names and periods")
    func names() {
        #expect(ErrorCategory.grammaticalCase.displayName == "Case")
        #expect(ErrorCategory.wordOrder.displayName == "Word order")
        #expect(ErrorCategory.falseFriend.displayName == "False friend")
        #expect(Set(ErrorCategory.allCases.map(\.displayName)).count == ErrorCategory.allCases.count)
        #expect(ProgressPeriod.allCases.map(\.title) == ["Last 7 days", "Last 30 days", "Last 90 days"])
        #expect(ProgressPeriod.allCases.map(\.bucketDays) == [1, 7, 7])
        #expect(ProgressReport.minimumWords == 300)
    }
}
