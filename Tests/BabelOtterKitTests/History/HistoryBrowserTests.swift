import Foundation
import Testing

@testable import BabelOtterKit

/// An in-memory store that counts reads and can be told to fail them.
final class ScriptedHistoryStore: HistoryStore {
    let inner = InMemoryHistoryStore()
    var reads = 0
    var failing = false

    func add(_ record: HistoryRecord) throws -> Int64 { try inner.add(record) }

    func page(matching term: String?, before: HistoryCursor?, limit: Int) throws -> [HistoryRecord] {
        reads += 1
        if failing { throw HistoryStoreError.statementFailed("disk I/O error") }
        return try inner.page(matching: term, before: before, limit: limit)
    }
}

@Suite("The History window's list pages, searches and reloads")
struct HistoryBrowserTests {

    /// `count` records, "r0" oldest; even ones contain "even".
    private func store(_ count: Int) throws -> ScriptedHistoryStore {
        let store = ScriptedHistoryStore()
        for index in 0..<count {
            let parity = index % 2 == 0 ? "even" : "odd"
            _ = try store.add(.sample(
                date: Date(timeIntervalSince1970: Double(1_000 + index)), source: "r\(index) \(parity)"))
        }
        return store
    }

    private func sources(_ browser: HistoryBrowser) -> [String] {
        browser.records.map { String($0.source.value.prefix(while: { $0 != " " })) }
    }

    @Test("the first page loads at once, newest first")
    func firstPage() throws {
        let browser = HistoryBrowser(store: try store(5), unavailable: nil, pageSize: 3)
        #expect(sources(browser) == ["r4", "r3", "r2"])
        #expect(browser.hasMore)
        #expect(browser.term == nil)
        #expect(browser.problem == nil)
    }

    @Test("there is more exactly while older records exist")
    func hasMoreIsExact() throws {
        #expect(HistoryBrowser(store: try store(4), unavailable: nil, pageSize: 3).hasMore)
        #expect(!HistoryBrowser(store: try store(3), unavailable: nil, pageSize: 3).hasMore)
        #expect(!HistoryBrowser(store: try store(0), unavailable: nil, pageSize: 3).hasMore)
    }

    @Test("loading more appends the next page, then stops")
    func loadMore() throws {
        let backing = try store(7)
        let browser = HistoryBrowser(store: backing, unavailable: nil, pageSize: 3)
        browser.loadMore()
        #expect(sources(browser) == ["r6", "r5", "r4", "r3", "r2", "r1"])
        #expect(browser.hasMore)
        browser.loadMore()
        #expect(sources(browser) == ["r6", "r5", "r4", "r3", "r2", "r1", "r0"])
        #expect(!browser.hasMore)
        let reads = backing.reads
        browser.loadMore()
        #expect(backing.reads == reads)
        #expect(browser.records.count == 7)
    }

    @Test("a search replaces the list and pages its own matches")
    func search() throws {
        let browser = HistoryBrowser(store: try store(9), unavailable: nil, pageSize: 3)
        browser.loadMore()
        browser.search("  EVEN ")
        #expect(browser.term == "EVEN")
        #expect(sources(browser) == ["r8", "r6", "r4"])
        #expect(browser.hasMore)
        browser.loadMore()
        #expect(sources(browser) == ["r8", "r6", "r4", "r2", "r0"])
        #expect(!browser.hasMore)
        browser.search("")
        #expect(browser.term == nil)
        #expect(sources(browser) == ["r8", "r7", "r6"])
    }

    @Test("the term in force again reads nothing")
    func sameTerm() throws {
        let backing = try store(4)
        let browser = HistoryBrowser(store: backing, unavailable: nil, pageSize: 3)
        browser.search("even")
        let reads = backing.reads
        browser.search(" even")
        #expect(backing.reads == reads)
        browser.search("odd")
        #expect(backing.reads == reads + 1)
    }

    @Test("a refresh puts a new record first and keeps as many loaded")
    func refresh() throws {
        let backing = try store(8)
        let browser = HistoryBrowser(store: backing, unavailable: nil, pageSize: 3)
        browser.loadMore()
        _ = try backing.add(.sample(date: Date(timeIntervalSince1970: 5_000), source: "new"))
        browser.refresh()
        #expect(sources(browser) == ["new", "r7", "r6", "r5", "r4", "r3"])
        #expect(browser.hasMore)
    }

    @Test("a refresh of a short list still reads a page")
    func refreshShort() throws {
        let backing = try store(1)
        let browser = HistoryBrowser(store: backing, unavailable: nil, pageSize: 3)
        _ = try backing.add(.sample(date: Date(timeIntervalSince1970: 5_000), source: "a"))
        _ = try backing.add(.sample(date: Date(timeIntervalSince1970: 5_001), source: "b"))
        browser.refresh()
        #expect(sources(browser) == ["b", "a", "r0"])
        #expect(!browser.hasMore)
    }

    @Test("a refresh keeps the term in force")
    func refreshKeepsTerm() throws {
        let backing = try store(4)
        let browser = HistoryBrowser(store: backing, unavailable: nil, pageSize: 3)
        browser.search("odd")
        _ = try backing.add(.sample(date: Date(timeIntervalSince1970: 5_000), source: "x even"))
        _ = try backing.add(.sample(date: Date(timeIntervalSince1970: 5_001), source: "y odd"))
        browser.refresh()
        #expect(browser.term == "odd")
        #expect(sources(browser) == ["y", "r3", "r1"])
    }

    @Test("a failed read keeps the list and says why; the next good read clears it")
    func failedRead() throws {
        let backing = try store(5)
        let browser = HistoryBrowser(store: backing, unavailable: nil, pageSize: 3)
        backing.failing = true
        browser.search("even")
        #expect(browser.problem == .reading("could not read (disk I/O error)"))
        #expect(browser.term == nil)
        #expect(sources(browser) == ["r4", "r3", "r2"])
        #expect(browser.hasMore)
        browser.loadMore()
        #expect(browser.records.count == 3)
        browser.refresh()
        #expect(browser.records.count == 3)
        backing.failing = false
        browser.loadMore()
        #expect(browser.problem == nil)
        #expect(sources(browser) == ["r4", "r3", "r2", "r1", "r0"])
    }

    @Test("a failed first read leaves an empty list with the reason")
    func failedFirstRead() throws {
        let backing = try store(2)
        backing.failing = true
        let browser = HistoryBrowser(store: backing, unavailable: nil, pageSize: 3)
        #expect(browser.records.isEmpty)
        #expect(!browser.hasMore)
        #expect(browser.problem == .reading("could not read (disk I/O error)"))
    }

    @Test("with no store, the reason stays and nothing happens")
    func noStore() {
        let browser = HistoryBrowser(store: nil, unavailable: "its folder syncs to iCloud", pageSize: 3)
        browser.search("x")
        browser.loadMore()
        browser.refresh()
        #expect(browser.problem == .unavailable("its folder syncs to iCloud"))
        #expect(browser.records.isEmpty)
        #expect(browser.term == nil)
        #expect(!browser.hasMore)
        #expect(HistoryBrowser(store: nil, unavailable: nil).problem == .unavailable("the database is not open"))
    }

    @Test("the default page holds 200")
    func defaultPage() throws {
        let browser = HistoryBrowser(store: try store(201), unavailable: nil)
        #expect(browser.records.count == 200)
        #expect(browser.hasMore)
        #expect(HistoryBrowser.pageSize == 200)
    }

    @Test("a page size below one is read as one")
    func tinyPage() throws {
        let browser = HistoryBrowser(store: try store(2), unavailable: nil, pageSize: 0)
        #expect(sources(browser) == ["r1"])
        #expect(browser.hasMore)
    }
}
