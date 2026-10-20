import Foundation
import SQLite3
import Testing

@testable import BabelOtterKit

@Suite("History is kept in a private SQLite file")
struct SQLiteHistoryStoreTests {

    private func folder() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "babelotter-history-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false))
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    /// Runs SQL on the file directly, as another program would.
    private func raw(_ url: URL, _ sql: String) {
        var handle: OpaquePointer?
        sqlite3_open(url.path(percentEncoded: false), &handle)
        sqlite3_exec(handle, sql, nil, nil, nil)
        sqlite3_close(handle)
    }

    private func expectCannotOpen(_ url: URL) {
        do {
            _ = try SQLiteHistoryStore.open(at: url)
            Issue.record("opened a file that is not a history database")
        } catch let error as HistoryStoreError {
            guard case .cannotOpen = error else {
                Issue.record("expected cannotOpen, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test("a new file is readable by its owner only")
    func newFileMode() throws {
        let url = try folder().appending(path: "history.sqlite")
        _ = try SQLiteHistoryStore.open(at: url)
        #expect(try permissions(url) == 0o600)
    }

    @Test("an existing file readable by others is locked down on open")
    func existingFileMode() throws {
        let url = try folder().appending(path: "history.sqlite")
        FileManager.default.createFile(
            atPath: url.path(percentEncoded: false), contents: nil,
            attributes: [.posixPermissions: 0o644])
        _ = try SQLiteHistoryStore.open(at: url)
        #expect(try permissions(url) == 0o600)
    }

    @Test("the file is excluded from backup")
    func excludedFromBackup() throws {
        let url = try folder().appending(path: "history.sqlite")
        _ = try SQLiteHistoryStore.open(at: url)
        let fresh = URL(filePath: url.path(percentEncoded: false))
        let values = try fresh.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("deleted text is overwritten and no write-ahead log is kept")
    func pragmas() throws {
        let store = try SQLiteHistoryStore.open(at: try folder().appending(path: "history.sqlite"))
        #expect(try store.pragmaValue("secure_delete") == "1")
        #expect(try store.pragmaValue("journal_mode") == "delete")
        #expect(try store.pragmaValue("user_version") == "1")
    }

    @Test("records survive closing and reopening")
    func reopen() throws {
        let url = try folder().appending(path: "history.sqlite")
        do {
            let store = try SQLiteHistoryStore.open(at: url)
            _ = try store.add(.sample(source: "kept"))
        }
        let again = try SQLiteHistoryStore.open(at: url)
        #expect(try again.recent(limit: 5).map(\.source.value) == ["kept"])
        #expect(try again.pragmaValue("user_version") == "1")
    }

    @Test("a file from a newer version is refused, not altered")
    func newerSchema() throws {
        let url = try folder().appending(path: "history.sqlite")
        do { _ = try SQLiteHistoryStore.open(at: url) }
        raw(url, "PRAGMA user_version = 2")
        #expect(throws: HistoryStoreError.newerSchema(2)) {
            _ = try SQLiteHistoryStore.open(at: url)
        }
    }

    @Test("a newer file in another journal mode is refused without a byte changed")
    func newerSchemaUntouched() throws {
        let url = try folder().appending(path: "history.sqlite")
        raw(url, "PRAGMA journal_mode = WAL; CREATE TABLE later (x); PRAGMA user_version = 2;")
        let before = try Data(contentsOf: url)
        #expect(throws: HistoryStoreError.newerSchema(2)) {
            _ = try SQLiteHistoryStore.open(at: url)
        }
        let after = try Data(contentsOf: url)
        // Bytes 18 and 19 of the header are 2 in WAL mode, 1 in rollback mode.
        #expect(Array(after[18...19]) == [2, 2])
        #expect(after == before)
    }

    @Test("a record is still saved while another program is briefly reading the file")
    func waitsForReader() throws {
        let url = try folder().appending(path: "history.sqlite")
        let store = try SQLiteHistoryStore.open(at: url)
        _ = try store.add(.sample(source: "first"))
        // Another program (the sqlite3 shell, a browser) holds a read lock...
        var reader: OpaquePointer?
        sqlite3_open(url.path(percentEncoded: false), &reader)
        sqlite3_exec(reader, "BEGIN; SELECT count(*) FROM records;", nil, nil, nil)
        // ...and lets go a moment later.
        let held = UncheckedReader(reader)
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(100)) {
            sqlite3_exec(held.pointer, "COMMIT", nil, nil, nil)
            sqlite3_close(held.pointer)
        }
        _ = try store.add(.sample(source: "second"))
        #expect(try store.recent(limit: 5).count == 2)
    }

    @Test("a file that is not a database cannot be opened")
    func notADatabase() throws {
        let url = try folder().appending(path: "history.sqlite")
        let bytes = Data(String(repeating: "not a database ", count: 200).utf8)
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: bytes)
        expectCannotOpen(url)
    }

    @Test("a missing folder cannot be opened")
    func missingFolder() throws {
        expectCannotOpen(try folder().appending(path: "absent/history.sqlite"))
    }

    @Test("a row with an action this build does not know is skipped")
    func unknownAction() throws {
        let url = try folder().appending(path: "history.sqlite")
        let store = try SQLiteHistoryStore.open(at: url)
        _ = try store.add(.sample(source: "known"))
        raw(url, """
            INSERT INTO records (created_at, action, source_language, model, source_text, result_text)
            VALUES (1, 'summarize', 'en', 'm', 's', 'r')
            """)
        #expect(try store.recent(limit: 5).map(\.source.value) == ["known"])
    }

    @Test("a row with an unknown action does not shorten a page")
    func unknownActionKeepsPageFull() throws {
        let url = try folder().appending(path: "history.sqlite")
        let store = try SQLiteHistoryStore.open(at: url)
        _ = try store.add(.sample(date: Date(timeIntervalSince1970: 1), source: "older"))
        raw(url, """
            INSERT INTO records (created_at, action, source_language, model, source_text, result_text)
            VALUES (2, 'summarize', 'en', 'm', 's', 'r')
            """)
        _ = try store.add(.sample(date: Date(timeIntervalSince1970: 3), source: "newer"))
        #expect(try store.recent(limit: 2).map(\.source.value) == ["newer", "older"])
    }

    @Test("after Clear All, the file holds none of the text and is back to its fresh size")
    func clearLeavesNoRemnant() throws {
        let folder = try folder()
        let fresh = folder.appending(path: "fresh.sqlite")
        _ = try SQLiteHistoryStore.open(at: fresh)
        let url = folder.appending(path: "history.sqlite")
        let store = try SQLiteHistoryStore.open(at: url)
        let marker = "Geheimnis-\u{00DC}bersetzung-7f3a"
        for index in 0..<300 {
            _ = try store.add(.sample(
                source: "\(marker) \(index) " + String(repeating: "Text ", count: 200),
                result: "\(marker) result \(index)"))
        }
        try store.deleteAll()
        let bytes = try Data(contentsOf: url)
        #expect(bytes.range(of: Data(marker.utf8)) == nil)
        #expect(bytes.range(of: Data("Text Text".utf8)) == nil)
        let freshSize = try Data(contentsOf: fresh).count
        #expect(bytes.count <= freshSize + 4_096)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false) + "-journal"))
    }

    @Test("records deleted for being old leave none of their text in the file")
    func pruneLeavesNoRemnant() throws {
        let url = try folder().appending(path: "history.sqlite")
        let store = try SQLiteHistoryStore.open(at: url)
        let marker = "Abgelaufen-\u{00E9}t\u{00E9}-91c2"
        _ = try store.add(.sample(date: Date(timeIntervalSince1970: 1), source: marker, result: marker))
        _ = try store.add(.sample(date: Date(timeIntervalSince1970: 9), source: "kept", result: "kept"))
        #expect(try store.deleteOlder(than: Date(timeIntervalSince1970: 5)) == 1)
        let bytes = try Data(contentsOf: url)
        #expect(bytes.range(of: Data(marker.utf8)) == nil)
        #expect(bytes.range(of: Data("kept".utf8)) != nil)
    }

    @Test("search characters SQL treats specially are matched literally")
    func literalTerm() throws {
        let store = try SQLiteHistoryStore.open(at: try folder().appending(path: "history.sqlite"))
        for text in ["100%", "a_b", "it's", "back\\slash", "plain"] {
            _ = try store.add(.sample(source: text))
        }
        #expect(try store.page(matching: "%", before: nil, limit: 9).map(\.source.value) == ["100%"])
        #expect(try store.page(matching: "_", before: nil, limit: 9).map(\.source.value) == ["a_b"])
        #expect(try store.page(matching: "'", before: nil, limit: 9).map(\.source.value) == ["it's"])
        #expect(try store.page(matching: "\\", before: nil, limit: 9).map(\.source.value) == ["back\\slash"])
    }

    @Test("search reads past an embedded NUL")
    func searchAfterNul() throws {
        let store = try SQLiteHistoryStore.open(at: try folder().appending(path: "history.sqlite"))
        _ = try store.add(.sample(source: "a\u{0000}needle"))
        #expect(try store.page(matching: "needle", before: nil, limit: 9).count == 1)
    }

    @Test("the application support folder is refused when it syncs to iCloud")
    func refusesICloud() throws {
        let home = try folder()
        let locator = StorageLocator(
            home: home, iCloudRoots: [home.appending(path: "Library")])
        #expect(throws: StorageLocationError.self) {
            _ = try SQLiteHistoryStore.inApplicationSupport(locator: locator)
        }
    }

    @Test("the application support folder holds history.sqlite")
    func inApplicationSupport() throws {
        let home = try folder()
        let locator = StorageLocator(home: home, iCloudRoots: [])
        _ = try SQLiteHistoryStore.inApplicationSupport(locator: locator)
        let file = locator.applicationSupportDirectory().appending(path: SQLiteHistoryStore.fileName)
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }
}

/// Carries a test-only connection to the thread that releases it.
private struct UncheckedReader: @unchecked Sendable {
    let pointer: OpaquePointer?
    init(_ pointer: OpaquePointer?) { self.pointer = pointer }
}
