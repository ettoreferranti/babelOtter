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
}
