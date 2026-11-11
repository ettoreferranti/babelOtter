import Foundation

@testable import BabelOtterKit

/// Dates and records for the learning tests: a Gregorian calendar in UTC
/// with weeks from Monday. 2026-11-09 is a Monday.
enum LearningFixtures {

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.firstWeekday = 2
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? Date()
    }

    static func day(_ year: Int, _ month: Int, _ day: Int) -> LearningDay {
        LearningDay(number: year * 10_000 + month * 100 + day)
    }

    static let english = LanguageCode("en")
    static let german = LanguageCode("de-ch")

    static func correct(
        _ date: Date, words: Int = 20, _ categories: [ErrorCategory] = [.gender],
        language: LanguageCode = german, result: String = "x"
    ) -> HistoryRecord {
        HistoryRecord(
            date: date, action: .correct, sourceLanguage: language, targetLanguage: nil,
            profileID: "colleagues", model: "m", sourceBundleID: nil, sourceAppName: nil,
            source: UserText("x"), result: UserText(result), wordCount: words,
            mistakes: categories.map { Mistake.sample($0) })
    }

    static func explain(_ date: Date, language: LanguageCode = german) -> HistoryRecord {
        HistoryRecord(
            date: date, action: .explain, sourceLanguage: language, targetLanguage: english,
            profileID: nil, model: "m", sourceBundleID: nil, sourceAppName: nil,
            source: UserText("x"), result: UserText("y"))
    }

    static func context(goal: Int = 3, corrections: [CorrectionStats] = []) -> LearningContext {
        LearningContext(
            goal: goal, myLanguage: english, languages: LanguageConfig.shippedDefaults,
            calendar: calendar, corrections: corrections)
    }

    /// A log with these days, through the rules' own door.
    static func log(_ days: [LearningDay]) -> LearningLog {
        var log = LearningLog()
        for day in days { log.add(day) }
        return log
    }
}
