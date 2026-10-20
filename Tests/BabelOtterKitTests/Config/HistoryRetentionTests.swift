import Foundation
import Testing

@testable import BabelOtterKit

@Suite("retentionDays is a number of days, unlimited or off")
struct HistoryRetentionTests {

    private struct Holder: Codable, Equatable {
        let retentionDays: HistoryRetention
    }

    private func decode(_ value: String) throws -> HistoryRetention {
        try JSONDecoder().decode(Holder.self, from: Data(#"{"retentionDays": \#(value)}"#.utf8))
            .retentionDays
    }

    @Test("numbers of 1 or more and the two words are read", arguments: [
        ("90", HistoryRetention.days(90)), ("1", .days(1)),
        (#""unlimited""#, .unlimited), (#""UNLIMITED""#, .unlimited),
        (#""off""#, .off), (#"" Off ""#, .off), (#""\noff\t""#, .off),
    ])
    func accepted(written: String, expected: HistoryRetention) throws {
        #expect(try decode(written) == expected)
    }

    @Test("anything else names the accepted forms", arguments: [
        "0", "-5", "1.5", #""never""#, #""""#, "null", "true", #""90""#, "[90]",
    ])
    func refused(written: String) {
        do {
            _ = try decode(written)
            Issue.record("\(written) was accepted")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.debugDescription == HistoryRetention.expected)
            #expect(context.codingPath.map(\.stringValue) == ["retentionDays"])
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("written back as a number or a word")
    func encoding() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        func text(_ retention: HistoryRetention) throws -> String {
            String(decoding: try encoder.encode(Holder(retentionDays: retention)), as: UTF8.self)
        }
        #expect(try text(.days(90)) == #"{"retentionDays":90}"#)
        #expect(try text(.unlimited) == #"{"retentionDays":"unlimited"}"#)
        #expect(try text(.off) == #"{"retentionDays":"off"}"#)
        for retention in [HistoryRetention.days(3), .unlimited, .off] {
            #expect(try decode(String(try text(retention).dropFirst(17).dropLast())) == retention)
        }
    }

    @Test("the cutoff is whole days back, and none without a number")
    func cutoff() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(HistoryRetention.days(1).cutoff(now: now) == Date(timeIntervalSince1970: 913_600))
        #expect(HistoryRetention.days(2).cutoff(now: now) == Date(timeIntervalSince1970: 827_200))
        #expect(HistoryRetention.unlimited.cutoff(now: now) == nil)
        #expect(HistoryRetention.off.cutoff(now: now) == nil)
        #expect(HistoryRetention.days(Int.max).cutoff(now: now) != nil)
        #expect(HistoryRetention.default == .days(90))
    }
}
