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
        #expect(try store.pragmaValue("user_version") == "2")
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
        #expect(try again.pragmaValue("user_version") == "2")
    }

    @Test("a file from a newer version is refused, not altered")
    func newerSchema() throws {
        let url = try folder().appending(path: "history.sqlite")
        do { _ = try SQLiteHistoryStore.open(at: url) }
        raw(url, "PRAGMA user_version = 3")
        #expect(throws: HistoryStoreError.newerSchema(3)) {
            _ = try SQLiteHistoryStore.open(at: url)
        }
    }

    @Test("a newer file in another journal mode is refused without a byte changed")
    func newerSchemaUntouched() throws {
        let url = try folder().appending(path: "history.sqlite")
        raw(url, "PRAGMA journal_mode = WAL; CREATE TABLE later (x); PRAGMA user_version = 3;")
        let before = try Data(contentsOf: url)
        #expect(throws: HistoryStoreError.newerSchema(3)) {
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
        // ...and lets go a moment later -- on a thread of its own: the
        // shared queue can be busy with the tests running in parallel, and
        // a release later than the 500 ms busy timeout failed CI (PR #107).
        let held = UncheckedReader(reader)
        let release = Thread {
            Thread.sleep(forTimeInterval: 0.1)
            sqlite3_exec(held.pointer, "COMMIT", nil, nil, nil)
            sqlite3_close(held.pointer)
        }
        release.start()
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
        #expect(try Data(contentsOf: url).range(of: Data(marker.utf8)) != nil)
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
        #expect(try Data(contentsOf: url).range(of: Data(marker.utf8)) != nil)
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

@Suite("History schema 2: Progress's mistakes in the SQLite file (#78)")
struct SQLiteHistorySchemaTwoTests {

    private func url() throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "babelotter-history-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "history.sqlite")
    }

    private func raw(_ url: URL, _ sql: String) {
        var handle: OpaquePointer?
        sqlite3_open(url.path(percentEncoded: false), &handle)
        sqlite3_exec(handle, sql, nil, nil, nil)
        sqlite3_close(handle)
    }

    private func rawCount(_ url: URL, _ table: String) -> Int {
        var handle: OpaquePointer?
        sqlite3_open(url.path(percentEncoded: false), &handle)
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(handle, "SELECT count(*) FROM \(table)", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        sqlite3_step(statement)
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// A file exactly as v1.1.0 wrote it, with one record.
    private func versionOneFile(_ url: URL) {
        raw(url, """
            CREATE TABLE records (
                id INTEGER PRIMARY KEY AUTOINCREMENT, created_at REAL NOT NULL,
                action TEXT NOT NULL, source_language TEXT NOT NULL, target_language TEXT,
                profile_id TEXT, model TEXT NOT NULL, source_bundle_id TEXT,
                source_app_name TEXT, source_text TEXT NOT NULL, result_text TEXT NOT NULL);
            INSERT INTO records (created_at, action, source_language, model, source_text, result_text)
                VALUES (1790000000, 'correct', 'de-ch', 'm', 'alt', 'old');
            PRAGMA user_version = 1;
            """)
    }

    @Test("a version 1 file is migrated, with its records intact")
    func migrates() throws {
        let url = try url()
        versionOneFile(url)
        let store = try SQLiteHistoryStore.open(at: url)
        #expect(try store.pragmaValue("user_version") == "2")
        #expect(try store.recent(limit: 5).map(\.source.value) == ["alt"])
        // From before #78: no word count, so not counted.
        #expect(try store.corrections(since: .distantPast).isEmpty)
        _ = try store.add(.correction(mistakes: [.sample()]))
        #expect(try store.corrections(since: .distantPast).flatMap(\.mistakes) == [.sample()])
    }

    @Test("a migrated file opens again without migrating twice")
    func migratedReopens() throws {
        let url = try url()
        versionOneFile(url)
        do { _ = try SQLiteHistoryStore.open(at: url) }
        let again = try SQLiteHistoryStore.open(at: url)
        #expect(try again.recent(limit: 5).count == 1)
    }

    @Test("a mistake's fragments leave the file with retention and with Clear All")
    func noRemnant() throws {
        let url = try url()
        let store = try SQLiteHistoryStore.open(at: url)
        let old = "Fehler-alt-\u{00E4}-3c1d"
        let new = "Fehler-neu-\u{00F6}-8e2b"
        _ = try store.add(.correction(date: Date(timeIntervalSince1970: 1), mistakes: [.sample(original: old)]))
        _ = try store.add(.correction(date: Date(timeIntervalSince1970: 9), mistakes: [.sample(original: new)]))
        #expect(rawCount(url, "mistakes") == 2)
        _ = try store.deleteOlder(than: Date(timeIntervalSince1970: 5))
        #expect(rawCount(url, "mistakes") == 1)
        var bytes = try Data(contentsOf: url)
        #expect(bytes.range(of: Data(old.utf8)) == nil)
        #expect(bytes.range(of: Data(new.utf8)) != nil)
        try store.deleteAll()
        #expect(rawCount(url, "mistakes") == 0)
        bytes = try Data(contentsOf: url)
        #expect(bytes.range(of: Data(new.utf8)) == nil)
    }

    @Test("a mistake with a category this build does not know counts as Other")
    func unknownCategory() throws {
        let url = try url()
        let store = try SQLiteHistoryStore.open(at: url)
        _ = try store.add(.correction(mistakes: [.sample()]))
        raw(url, "UPDATE mistakes SET category = 'tense'")
        #expect(try store.corrections(since: .distantPast).flatMap(\.mistakes).map(\.category) == [.other])
    }

    @Test("a record whose mistake cannot be written is not kept either")
    func atomic() throws {
        let url = try url()
        let store = try SQLiteHistoryStore.open(at: url)
        raw(url, "CREATE TRIGGER refuse BEFORE INSERT ON mistakes BEGIN SELECT RAISE(ABORT, 'no'); END;")
        #expect(throws: HistoryStoreError.self) {
            _ = try store.add(.correction(mistakes: [.sample()]))
        }
        #expect(try store.count() == 0)
        _ = try store.add(.sample())
        #expect(try store.count() == 1)
    }
}
