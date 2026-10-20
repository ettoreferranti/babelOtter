import Foundation

/// Where history is kept (#67). #68 adds search and #69 deletion when they
/// need them.
public protocol HistoryStore: Sendable {
    /// Keeps the record and returns its new id. The record's own `id` is
    /// ignored.
    func add(_ record: HistoryRecord) throws -> Int64
    /// Newest first (by date, then id), at most `limit`; none for a limit
    /// below 1.
    func recent(limit: Int) throws -> [HistoryRecord]
}

/// Never carries record text: only SQLite's or the file system's message.
public enum HistoryStoreError: Error, Equatable {
    case cannotOpen(String)
    case statementFailed(String)
    /// The file's `user_version`, higher than this build understands.
    case newerSchema(Int)
}

/// A `HistoryStore` in memory, for tests.
public final class InMemoryHistoryStore: HistoryStore, @unchecked Sendable {

    private var records: [HistoryRecord] = []
    private var nextID: Int64 = 1
    private let lock = NSLock()

    public init() {}

    public func add(_ record: HistoryRecord) throws -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let id = nextID
        nextID += 1
        var stored = record
        stored.id = id
        records.append(stored)
        return id
    }

    public func recent(limit: Int) throws -> [HistoryRecord] {
        lock.lock()
        defer { lock.unlock() }
        if limit < 1 { return [] }
        return Array(records.sorted(by: Self.isNewer).prefix(limit))
    }

    /// Later date first; for the same date, the higher id.
    static func isNewer(_ lhs: HistoryRecord, _ rhs: HistoryRecord) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return (lhs.id ?? 0) > (rhs.id ?? 0)
    }
}
