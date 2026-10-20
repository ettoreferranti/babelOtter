import Foundation
import Testing

@testable import BabelOtterKit

/// Every store, the same promises.
enum StoreKind: String, CaseIterable, CustomTestStringConvertible {
    case memory
    case sqlite

    var testDescription: String { rawValue }

    func make() throws -> any HistoryStore {
        switch self {
        case .memory:
            return InMemoryHistoryStore()
        case .sqlite:
            let folder = URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "babelotter-history-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return try SQLiteHistoryStore.open(at: folder.appending(path: "history.sqlite"))
        }
    }
}

@Suite("Every history store keeps records the same way")
struct HistoryStoreContractTests {

    @Test("every field comes back as it went in", arguments: StoreKind.allCases)
    func roundTrip(kind: StoreKind) throws {
        let store = try kind.make()
        let record = HistoryRecord.sample(
            action: .explain, targetLanguage: LanguageCode("en"), profileID: nil,
            bundleID: nil, appName: nil,
            // eszett, otter emoji, quotes, an injection attempt, line breaks
            source: "Gr\u{00FC}\u{00DF}e \u{1F9A6} \"x\" 'y' '); DROP TABLE records; --\nZeile 2\r\n",
            result: "Greetings\n\n- \"Gr\u{00FC}\u{00DF}e\": greetings")
        let id = try store.add(record)
        var expected = record
        expected.id = id
        #expect(try store.recent(limit: 10) == [expected])
    }

    @Test("an embedded NUL and a long text come back whole", arguments: StoreKind.allCases)
    func awkwardText(kind: StoreKind) throws {
        let store = try kind.make()
        let long = String(repeating: "Absatz mit Text. ", count: 6_000)
        let record = HistoryRecord.sample(source: "a\u{0000}b", result: long)
        _ = try store.add(record)
        let back = try store.recent(limit: 1)
        #expect(back.first?.source == UserText("a\u{0000}b"))
        #expect(back.first?.result == UserText(long))
    }

    @Test("newest first, and limit caps the count", arguments: StoreKind.allCases)
    func newestFirst(kind: StoreKind) throws {
        let store = try kind.make()
        let old = HistoryRecord.sample(date: Date(timeIntervalSince1970: 1_000), source: "old")
        let new = HistoryRecord.sample(date: Date(timeIntervalSince1970: 3_000), source: "new")
        let mid = HistoryRecord.sample(date: Date(timeIntervalSince1970: 2_000), source: "mid")
        _ = try store.add(old)
        _ = try store.add(new)
        _ = try store.add(mid)
        let sources = try store.recent(limit: 2).map(\.source.value)
        #expect(sources == ["new", "mid"])
    }

    @Test("records with the same date come back newest id first", arguments: StoreKind.allCases)
    func sameDate(kind: StoreKind) throws {
        let store = try kind.make()
        let first = try store.add(.sample(source: "first"))
        let second = try store.add(.sample(source: "second"))
        let ids = try store.recent(limit: 5).compactMap(\.id)
        #expect(ids == [second, first])
    }

    @Test("ids increase and the record's own id is ignored", arguments: StoreKind.allCases)
    func ids(kind: StoreKind) throws {
        let store = try kind.make()
        var claimed = HistoryRecord.sample()
        claimed.id = 999
        let first = try store.add(claimed)
        let second = try store.add(claimed)
        #expect(second > first)
        #expect(first != 999)
    }

    @Test("a limit of zero or less returns nothing", arguments: StoreKind.allCases)
    func emptyLimit(kind: StoreKind) throws {
        let store = try kind.make()
        _ = try store.add(.sample())
        #expect(try store.recent(limit: 0).isEmpty)
        #expect(try store.recent(limit: -1).isEmpty)
    }

    @Test("an empty store returns nothing", arguments: StoreKind.allCases)
    func empty(kind: StoreKind) throws {
        #expect(try kind.make().recent(limit: 10).isEmpty)
    }

    // MARK: - Paging and search (#68)

    @Test("a page starts strictly after its cursor, same-date records by id", arguments: StoreKind.allCases)
    func cursor(kind: StoreKind) throws {
        let store = try kind.make()
        // Fractional dates, as Date() gives, so equality is tested in earnest.
        let early = Date(timeIntervalSince1970: 1_790_000_000.123_456)
        let late = Date(timeIntervalSince1970: 1_790_000_100.654_321)
        _ = try store.add(.sample(date: early, source: "a"))
        let b = try store.add(.sample(date: late, source: "b"))
        _ = try store.add(.sample(date: late, source: "c"))
        let newest = try store.page(matching: nil, before: nil, limit: 1)
        #expect(newest.map(\.source.value) == ["c"])
        let cursor = try #require(newest.first.flatMap { HistoryCursor($0) })
        let next = try store.page(matching: nil, before: cursor, limit: 10)
        #expect(next.map(\.source.value) == ["b", "a"])
        let afterB = try store.page(
            matching: nil, before: HistoryCursor(date: late, id: b), limit: 10)
        #expect(afterB.map(\.source.value) == ["a"])
    }

    @Test("pages read one after another cover every record once", arguments: StoreKind.allCases)
    func pagesCoverAll(kind: StoreKind) throws {
        let store = try kind.make()
        for index in 0..<7 {
            _ = try store.add(.sample(
                date: Date(timeIntervalSince1970: Double(1_000 + index / 2)), source: "r\(index)"))
        }
        var seen: [String] = []
        var cursor: HistoryCursor?
        for _ in 0..<5 {
            let page = try store.page(matching: nil, before: cursor, limit: 3)
            seen += page.map(\.source.value)
            guard let last = page.last else { break }
            cursor = HistoryCursor(last)
        }
        #expect(seen == ["r6", "r5", "r4", "r3", "r2", "r1", "r0"])
    }

    @Test("a term finds the source or the result, ignoring case and accents", arguments: StoreKind.allCases)
    func search(kind: StoreKind) throws {
        let store = try kind.make()
        _ = try store.add(.sample(source: "Die \u{00DC}ber-Sitzung", result: "The meeting"))
        _ = try store.add(.sample(source: "Hallo", result: "Hello UBER fans"))
        _ = try store.add(.sample(source: "Hallo", result: "Hello"))
        let found = try store.page(matching: "uber", before: nil, limit: 10)
        #expect(found.map(\.result.value) == ["Hello UBER fans", "The meeting"])
        #expect(try store.page(matching: "nothing", before: nil, limit: 10).isEmpty)
    }

    @Test("a term and a cursor combine, and the limit counts matches", arguments: StoreKind.allCases)
    func searchPaged(kind: StoreKind) throws {
        let store = try kind.make()
        for index in 0..<5 {
            _ = try store.add(.sample(source: index % 2 == 0 ? "match \(index)" : "other \(index)"))
        }
        let first = try store.page(matching: "match", before: nil, limit: 2)
        #expect(first.map(\.source.value) == ["match 4", "match 2"])
        let rest = try store.page(matching: "match", before: first.last.flatMap { HistoryCursor($0) }, limit: 2)
        #expect(rest.map(\.source.value) == ["match 0"])
    }

    @Test("recent is the first page of everything", arguments: StoreKind.allCases)
    func recentIsFirstPage(kind: StoreKind) throws {
        let store = try kind.make()
        for index in 0..<4 { _ = try store.add(.sample(source: "r\(index)")) }
        #expect(try store.recent(limit: 3) == store.page(matching: nil, before: nil, limit: 3))
        #expect(try store.page(matching: "r", before: nil, limit: 0).isEmpty)
    }
}
