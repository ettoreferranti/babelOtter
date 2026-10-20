import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Where a page of history ends")
struct HistoryCursorTests {

    private let date = Date(timeIntervalSince1970: 2_000)

    @Test("a kept record gives its date and id; an unkept one, none")
    func fromRecord() {
        var record = HistoryRecord.sample(date: date)
        #expect(HistoryCursor(record) == nil)
        record.id = 7
        #expect(HistoryCursor(record) == HistoryCursor(date: date, id: 7))
    }

    @Test("older dates, and lower ids on the same date, come after")
    func precedes() {
        let cursor = HistoryCursor(date: date, id: 5)
        var older = HistoryRecord.sample(date: Date(timeIntervalSince1970: 1_999))
        older.id = 9
        var newer = HistoryRecord.sample(date: Date(timeIntervalSince1970: 2_001))
        newer.id = 1
        var lower = HistoryRecord.sample(date: date)
        lower.id = 4
        var same = HistoryRecord.sample(date: date)
        same.id = 5
        var higher = HistoryRecord.sample(date: date)
        higher.id = 6
        #expect(cursor.precedes(older))
        #expect(!cursor.precedes(newer))
        #expect(cursor.precedes(lower))
        #expect(!cursor.precedes(same))
        #expect(!cursor.precedes(higher))
        // A record without an id counts as id 0 on the same date.
        #expect(cursor.precedes(.sample(date: date)))
        #expect(!HistoryCursor(date: date, id: 0).precedes(.sample(date: date)))
    }
}
