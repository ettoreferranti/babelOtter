import Foundation
import Testing

@testable import BabelOtterKit

@Suite("The learning log: days, totals and milestones, never text (#136)")
struct LearningLogTests {

    private typealias Fixtures = LearningFixtures

    @Test("a day is the calendar's year, month and day, in one number")
    func dayFromDate() {
        let day = LearningDay(Fixtures.date(2026, 11, 9, hour: 23), calendar: Fixtures.calendar)
        #expect(day.number == 20_261_109)
        #expect(day == Fixtures.day(2026, 11, 9))
        var zurich = Fixtures.calendar
        zurich.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .gmt
        #expect(LearningDay(Fixtures.date(2026, 11, 9, hour: 23), calendar: zurich).number == 20_261_110)
    }

    @Test("a day gives back noon of itself")
    func dayToDate() {
        let day = Fixtures.day(2026, 3, 7)
        #expect(day.date(calendar: Fixtures.calendar) == Fixtures.date(2026, 3, 7, hour: 12))
        #expect(Fixtures.day(2027, 12, 31).date(calendar: Fixtures.calendar) == Fixtures.date(2027, 12, 31, hour: 12))
    }

    @Test("a day is Gregorian whatever the Mac's calendar, in its time zone")
    func gregorianAlways() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let date = Fixtures.date(2026, 11, 9)
        #expect(LearningDay(date, calendar: buddhist).number == 20_261_109)
        #expect(Fixtures.day(2026, 11, 9).date(calendar: buddhist) == Fixtures.date(2026, 11, 9, hour: 12))
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        #expect(LearningDay(Fixtures.date(2026, 11, 9, hour: 16), calendar: japanese).number == 20_261_110)
    }

    @Test("days order by date")
    func ordering() {
        #expect(Fixtures.day(2026, 12, 31) < Fixtures.day(2027, 1, 1))
        #expect(!(Fixtures.day(2027, 1, 1) < Fixtures.day(2027, 1, 1)))
    }

    @Test("days are kept once, oldest first")
    func days() {
        var log = LearningLog()
        #expect(log.isEmpty)
        log.add(Fixtures.day(2026, 11, 10))
        log.add(Fixtures.day(2026, 11, 9))
        log.add(Fixtures.day(2026, 11, 10))
        #expect(log.days == [Fixtures.day(2026, 11, 9), Fixtures.day(2026, 11, 10)])
        #expect(log.has(Fixtures.day(2026, 11, 9)))
        #expect(!log.has(Fixtures.day(2026, 11, 11)))
        #expect(!log.isEmpty)
    }

    @Test("only the 400 most recent days are kept")
    func bound() {
        var log = LearningLog()
        for number in 1...LearningLog.maximumDays { log.add(LearningDay(number: number)) }
        #expect(log.days.count == 400)
        #expect(log.days.first == LearningDay(number: 1))
        log.add(LearningDay(number: 401))
        #expect(log.days.count == 400)
        #expect(log.days.first == LearningDay(number: 2))
        #expect(log.days.last == LearningDay(number: 401))
    }

    @Test("totals add up")
    func totals() {
        var log = LearningLog()
        log.addWords(120)
        log.addWords(30)
        log.addExplanation()
        log.addExplanation()
        #expect(log.wordsCorrected == 150)
        #expect(log.explanations == 2)
    }

    @Test("a milestone is earned once, with its first day")
    func earning() {
        var log = LearningLog()
        log.earn(.cleanText, on: Fixtures.day(2026, 11, 9))
        log.earn(.cleanText, on: Fixtures.day(2026, 11, 10))
        log.earn(.words(1_000), on: Fixtures.day(2026, 11, 10))
        #expect(log.earned == [
            EarnedMilestone(milestone: .cleanText, day: Fixtures.day(2026, 11, 9)),
            EarnedMilestone(milestone: .words(1_000), day: Fixtures.day(2026, 11, 10)),
        ])
        #expect(log.hasEarned(.cleanText))
        #expect(!log.hasEarned(.words(5_000)))
        #expect(!log.isEmpty)
    }

    @Test("the log round-trips through JSON, days as bare numbers")
    func json() throws {
        var log = Fixtures.log([Fixtures.day(2026, 11, 9)])
        log.addWords(1_200)
        log.addExplanation()
        log.earn(.firstSteps, on: Fixtures.day(2026, 11, 9))
        log.earn(.tamed(.grammaticalCase, LanguageCode("de")), on: Fixtures.day(2026, 11, 9))
        log.earn(.streak(4), on: Fixtures.day(2026, 11, 9))
        log.hintShown(on: Fixtures.day(2026, 11, 8))
        let data = try JSONEncoder().encode(log)
        #expect(try JSONDecoder().decode(LearningLog.self, from: data) == log)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"days\":[20261109]"))
        #expect(text.contains("\"lastHintDay\":20261108"))
    }

    @Test("a log from a newer version keeps all this one can read")
    func newerLog() throws {
        let json = """
            {"days":[20261110,20261109,20261110],"wordsCorrected":40,"somethingNew":true,
             "earned":[{"milestone":{"cleanText":{}},"day":20261109},
                       {"milestone":{"unheardOf":{"_0":3}},"day":20261109},
                       {"milestone":{"tamed":{"_0":"aspect","_1":"de"}},"day":20261109},
                       {"milestone":{"cleanText":{}},"day":20261110},
                       {"milestone":{"streak":{"_0":4}},"day":20261110}]}
            """
        let log = try JSONDecoder().decode(LearningLog.self, from: Data(json.utf8))
        #expect(log.days == [Fixtures.day(2026, 11, 9), Fixtures.day(2026, 11, 10)])
        #expect(log.wordsCorrected == 40)
        #expect(log.explanations == 0)
        #expect(log.lastHintDay == nil)
        #expect(log.earned == [
            EarnedMilestone(milestone: .cleanText, day: Fixtures.day(2026, 11, 9)),
            EarnedMilestone(milestone: .streak(4), day: Fixtures.day(2026, 11, 10)),
        ])
        #expect(try JSONDecoder().decode(LearningLog.self, from: Data("{}".utf8)) == LearningLog())
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LearningLog.self, from: Data(#"{"days":"none"}"#.utf8))
        }
    }

    @Test("an empty log round-trips without a hint day")
    func emptyJSON() throws {
        let data = try JSONEncoder().encode(LearningLog())
        let back = try JSONDecoder().decode(LearningLog.self, from: data)
        #expect(back == LearningLog())
        #expect(back.lastHintDay == nil)
    }
}

@Suite("Milestone names (#136)")
struct MilestoneTests {

    private let languages = LanguageConfig.shippedDefaults

    @Test("each kind has its title")
    func titles() {
        #expect(Milestone.firstSteps.title(languages: languages) == "First steps")
        #expect(Milestone.words(1_000).title(languages: languages) == "1,000 words")
        #expect(Milestone.words(10_000).title(languages: languages) == "10,000 words")
        #expect(Milestone.explanations(10).title(languages: languages) == "10 explanations")
        #expect(Milestone.cleanText.title(languages: languages) == "Clean text")
        #expect(Milestone.streak(4).title(languages: languages) == "4 weeks in a row")
    }

    @Test("a tamed category names the language by its base code")
    func tamed() {
        let german = Milestone.name(of: LanguageCode("de-ch"), in: languages)
        #expect(Milestone.tamed(.grammaticalCase, LanguageCode("de")).title(languages: languages)
            == "Case tamed in \(german)")
        #expect(Milestone.name(of: LanguageCode("de"), in: languages) == german)
        #expect(Milestone.name(of: LanguageCode("pt"), in: languages) == "pt")
        #expect(Milestone.tamed(.wordOrder, LanguageCode("pt")).title(languages: []) == "Word order tamed in pt")
    }

    @Test("numbers group in thousands")
    func grouped() {
        #expect(Milestone.grouped(0) == "0")
        #expect(Milestone.grouped(999) == "999")
        #expect(Milestone.grouped(1_000) == "1,000")
        #expect(Milestone.grouped(5_040) == "5,040")
        #expect(Milestone.grouped(12_345) == "12,345")
        #expect(Milestone.grouped(1_000_007) == "1,000,007")
    }

    @Test("the steps")
    func steps() {
        #expect(Milestone.wordSteps == [1_000, 5_000, 10_000])
        #expect(Milestone.explanationSteps == [10, 50])
        #expect(Milestone.streakSteps == [4, 12])
    }
}
