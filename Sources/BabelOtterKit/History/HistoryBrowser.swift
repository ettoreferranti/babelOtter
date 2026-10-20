import Foundation

/// Why the History window cannot show everything (#68).
public enum HistoryBrowserProblem: Equatable, Sendable {
    /// The store could not be opened: "History is not saved - <reason>".
    case unavailable(String)
    /// A page failed and what was loaded stays: "Could not read the
    /// history - <reason>".
    case reading(String)
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
        guard let page = read(term: term, before: HistoryCursor(last), count: pageSize) else { return }
        records += page.prefix(pageSize)
        hasMore = page.count > pageSize
    }

    /// Reloads from the top as many records as are loaded, at least a page:
    /// a new record comes first and the list keeps its length, so the
    /// oldest loaded one moves to the next page.
    public func refresh() {
        _ = reload(term: term, count: max(records.count, pageSize))
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
