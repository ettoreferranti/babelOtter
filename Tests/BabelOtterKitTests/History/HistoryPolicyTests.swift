import Foundation
import Testing

@testable import BabelOtterKit

@Suite("What history does under the configuration in use")
struct HistoryPolicyTests {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("a number of days records and prunes")
    func days() {
        let policy = HistoryPolicy(retention: .days(1), configurationIsFallback: false)
        #expect(policy == .keep(.days(1)))
        #expect(policy.records)
        #expect(policy.pruneCutoff(now: now) == Date(timeIntervalSince1970: 913_600))
        #expect(policy.menuNote == nil)
        #expect(policy.windowNote == nil)
    }

    @Test("unlimited records and never prunes")
    func unlimited() {
        let policy = HistoryPolicy(retention: .unlimited, configurationIsFallback: false)
        #expect(policy == .keep(.unlimited))
        #expect(policy.records)
        #expect(policy.pruneCutoff(now: now) == nil)
        #expect(policy.menuNote == nil)
    }

    @Test("off records nothing and deletes nothing")
    func off() {
        let policy = HistoryPolicy(retention: .off, configurationIsFallback: false)
        #expect(policy == .off)
        #expect(!policy.records)
        #expect(policy.pruneCutoff(now: now) == nil)
        #expect(policy.menuNote == "History: off")
        #expect(policy.windowNote == "History is off - nothing new is saved.")
    }

    @Test("a fallback configuration pauses history, whatever it says", arguments: [
        HistoryRetention.days(90), .unlimited, .off,
    ])
    func fallback(retention: HistoryRetention) {
        let policy = HistoryPolicy(retention: retention, configurationIsFallback: true)
        #expect(policy == .paused)
        #expect(!policy.records)
        #expect(policy.pruneCutoff(now: now) == nil)
        #expect(policy.menuNote == "History: off until config.json is fixed")
        #expect(policy.windowNote
            == "History is off until config.json is fixed - nothing new is saved.")
    }
}
