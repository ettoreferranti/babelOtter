import Foundation

/// Where history is kept (#67), paged and searched (#68). #69 adds deletion.
///
/// Not `Sendable`, and no store takes a lock: history is written on the main
/// actor when a popup closes. A lock would also hang mutation testing --
/// muter deletes `unlock()` as a side effect, and the next call then waits
/// forever, with no per-mutant timeout to end it (PR #105).
public protocol HistoryStore: AnyObject {
    /// Keeps the record and returns its new id. The record's own `id` is
    /// ignored.
    func add(_ record: HistoryRecord) throws -> Int64
    /// Newest first (by date, then id), at most `limit`; none for a limit
    /// below 1. Only records older than `before` when it is given, and only
    /// those `HistorySearch.matches` when `term` is given. `term` is used as
    /// given: callers pass `HistorySearch.normalized`.
    func page(matching term: String?, before: HistoryCursor?, limit: Int) throws -> [HistoryRecord]
}

extension HistoryStore {

    /// The newest `limit` records.
    public func recent(limit: Int) throws -> [HistoryRecord] {
        try page(matching: nil, before: nil, limit: limit)
    }
}

/// Never carries record text: only SQLite's or the file system's message.
public enum HistoryStoreError: Error, Equatable {
    case cannotOpen(String)
    case statementFailed(String)
    /// The file's `user_version`, higher than this build understands.
    case newerSchema(Int)
}

/// A `HistoryStore` in memory, for tests.
public final class InMemoryHistoryStore: HistoryStore {

    private var records: [HistoryRecord] = []
    private var nextID: Int64 = 1

    public init() {}

    public func add(_ record: HistoryRecord) throws -> Int64 {
        let id = nextID
        nextID += 1
        var stored = record
        stored.id = id
        records.append(stored)
        return id
    }

    public func page(matching term: String?, before: HistoryCursor?, limit: Int) throws -> [HistoryRecord] {
        if limit < 1 { return [] }
        var found = records.sorted(by: Self.isNewer)
        if let before { found = found.filter { before.precedes($0) } }
        if let term { found = found.filter { HistorySearch.matches($0, term) } }
        return Array(found.prefix(limit))
    }

    /// Later date first; for the same date, the higher id.
    static func isNewer(_ lhs: HistoryRecord, _ rhs: HistoryRecord) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return (lhs.id ?? 0) > (rhs.id ?? 0)
    }
}
