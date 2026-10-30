import Foundation

/// Where history is kept (#67), paged and searched (#68), pruned and
/// cleared (#69).
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
    /// Deletes every record dated before `date`; returns how many.
    func deleteOlder(than date: Date) throws -> Int
    /// Deletes every record and leaves no trace of them in storage.
    func deleteAll() throws
    /// How many records there are.
    func count() throws -> Int
    /// Every Correct record dated `date` or later that has a word count,
    /// oldest first, without its texts (#78).
    func corrections(since date: Date) throws -> [CorrectionStats]
}

/// One correction as Progress reads it (#78): when, in which language, how
/// many words, and the errors found. No source or result text.
public struct CorrectionStats: Sendable, Equatable {
    public let date: Date
    public let language: LanguageCode
    public let wordCount: Int
    public let mistakes: [Mistake]

    public init(date: Date, language: LanguageCode, wordCount: Int, mistakes: [Mistake]) {
        self.date = date
        self.language = language
        self.wordCount = wordCount
        self.mistakes = mistakes
    }
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

    public func deleteOlder(than date: Date) throws -> Int {
        let before = records.count
        var kept: [HistoryRecord] = []
        for record in records where record.date >= date { kept.append(record) }
        records = kept
        return before - records.count
    }

    public func deleteAll() throws {
        records.removeAll()
    }

    public func count() throws -> Int {
        records.count
    }

    public func corrections(since date: Date) throws -> [CorrectionStats] {
        var found: [CorrectionStats] = []
        for record in records.sorted(by: Self.isOlder) {
            if let stats = Self.stats(record, since: date) { found.append(stats) }
        }
        return found
    }

    static func stats(_ record: HistoryRecord, since date: Date) -> CorrectionStats? {
        guard case .correct = record.action else { return nil }
        guard let wordCount = record.wordCount else { return nil }
        if record.date < date { return nil }
        return CorrectionStats(
            date: record.date, language: record.sourceLanguage, wordCount: wordCount,
            mistakes: record.mistakes)
    }

    /// Earlier date first; for the same date, the lower id.
    static func isOlder(_ lhs: HistoryRecord, _ rhs: HistoryRecord) -> Bool {
        isNewer(rhs, lhs)
    }

    /// Later date first; for the same date, the higher id.
    static func isNewer(_ lhs: HistoryRecord, _ rhs: HistoryRecord) -> Bool {
        if lhs.date > rhs.date { return true }
        if lhs.date < rhs.date { return false }
        return (lhs.id ?? 0) > (rhs.id ?? 0)
    }
}
