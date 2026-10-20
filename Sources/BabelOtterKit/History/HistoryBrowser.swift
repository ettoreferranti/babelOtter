import Foundation

/// Why the History window cannot show everything (#68).
public enum HistoryBrowserProblem: Equatable, Sendable {
    /// The store could not be opened: "History is not saved - <reason>".
    case unavailable(String)
    /// A page failed and what was loaded stays: "Could not read the
    /// history - <reason>".
    case reading(String)
    /// Clear All failed and the records stay: "Could not clear the
    /// history - <reason>" (#69).
    case clearing(String)
}

/// What the History window shows, and how it pages (#68, `FR-HIS-02`).
///
/// Each read asks for one record more than it keeps, so `hasMore` is exact.
/// A failed read changes nothing but `problem`; the next good one clears it.
/// With no store, every method does nothing.
public final class HistoryBrowser {

    public static let pageSize = 200

    private let store: (any HistoryStore)?
    private let pageSize: Int

    public private(set) var records: [HistoryRecord] = []
    /// The normalized term in force; nil shows everything.
    public private(set) var term: String?
    /// True while older records exist.
    public private(set) var hasMore = false
    public private(set) var problem: HistoryBrowserProblem?

    /// `unavailable` says why `store` is nil. Loads the first page.
    public init(store: (any HistoryStore)?, unavailable: String?, pageSize: Int = HistoryBrowser.pageSize) {
        self.store = store
        self.pageSize = max(pageSize, 1)
        if store == nil {
            problem = .unavailable(unavailable ?? "the database is not open")
            return
        }
        _ = reload(term: nil, count: self.pageSize)
    }

    /// Replaces the list with the first page for `term`, once normalized.
    /// The term in force again does nothing.
    public func search(_ term: String) {
        let wanted = HistorySearch.normalized(term)
        if wanted == self.term { return }
        _ = reload(term: wanted, count: pageSize)
    }

    /// Appends the next page after the last record.
    public func loadMore() {
        guard hasMore else { return }
        guard let last = records.last else { return }
        // A nil cursor would read the first page again.
        guard let cursor = HistoryCursor(last) else { return }
        guard let page = read(term: term, before: cursor, count: pageSize) else { return }
        records += page.prefix(pageSize)
        hasMore = page.count > pageSize
    }

    /// Reloads from the top one more record than are loaded, at least a
    /// page: called once per saved record, so the new one comes first and
    /// every loaded record stays -- a selection on the oldest included.
    public func refresh() {
        _ = reload(term: term, count: max(records.count + 1, pageSize))
    }

    /// How many records there are, for Clear All's confirmation; nil with no
    /// store or when counting fails.
    public func count() -> Int? {
        guard let store else { return nil }
        return try? store.count()
    }

    /// Deletes every record, then shows the empty list for the term in
    /// force. False, with the reason in `problem`, when nothing was deleted.
    public func clearAll() -> Bool {
        guard let store else { return false }
        do {
            try store.deleteAll()
        } catch {
            problem = .clearing(HistoryProblem.clearing(error))
            return false
        }
        _ = reload(term: term, count: pageSize)
        return true
    }

    /// True when the read succeeded and the list now holds it.
    private func reload(term: String?, count: Int) -> Bool {
        guard let page = read(term: term, before: nil, count: count) else { return false }
        self.term = term
        records = Array(page.prefix(count))
        hasMore = page.count > count
        return true
    }

    /// `count + 1` records, or nil after recording why the read failed.
    private func read(term: String?, before: HistoryCursor?, count: Int) -> [HistoryRecord]? {
        guard let store else { return nil }
        do {
            let page = try store.page(matching: term, before: before, limit: count + 1)
            problem = nil
            return page
        } catch {
            problem = .reading(HistoryProblem.reading(error))
            return nil
        }
    }
}
