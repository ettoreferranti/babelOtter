import Foundation

/// Where a page of history ends: the last record's date and id (#68). The
/// next page holds only records strictly older -- an earlier date, or the
/// same date and a lower id -- so a record added at the top shifts nothing.
public struct HistoryCursor: Sendable, Equatable {
    public let date: Date
    public let id: Int64

    public init(date: Date, id: Int64) {
        self.date = date
        self.id = id
    }

    /// Nil for a record no store has kept.
    public init?(_ record: HistoryRecord) {
        guard let id = record.id else { return nil }
        self.init(date: record.date, id: id)
    }

    /// True when `record` belongs after this cursor.
    public func precedes(_ record: HistoryRecord) -> Bool {
        if record.date != date { return record.date < date }
        return (record.id ?? 0) < id
    }
}
