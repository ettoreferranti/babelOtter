import Foundation
import SQLite3

/// `HistoryStore` over the system SQLite library (#67, #68, `FR-HIS-01`,
/// `FR-HIS-02`, `FR-HIS-04`, `NFR-P7`).
///
/// The file is created `0600` before SQLite touches it and excluded from
/// backup. `secure_delete` overwrites deleted text and the rollback journal
/// leaves no `-wal` file holding it, so #69's Clear All needs no format
/// change. Every value is bound, never written into SQL.
public final class SQLiteHistoryStore: HistoryStore {

    public static let fileName = "history.sqlite"
    /// 2 adds Progress's word counts and mistakes (#78).
    static let schemaVersion = 2
    /// Bounded: a write runs on the main actor when a popup closes.
    static let busyTimeoutMilliseconds: Int32 = 500

    private static let createSchema = """
        BEGIN;
        CREATE TABLE records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at REAL NOT NULL,
            action TEXT NOT NULL,
            source_language TEXT NOT NULL,
            target_language TEXT,
            profile_id TEXT,
            model TEXT NOT NULL,
            source_bundle_id TEXT,
            source_app_name TEXT,
            source_text TEXT NOT NULL,
            result_text TEXT NOT NULL
        );
        PRAGMA user_version = 1;
        COMMIT;
        """

    /// Version 1 to 2 (#78), in one transaction. The trigger makes every
    /// existing `DELETE` on records -- retention, Clear All -- take the
    /// record's mistakes with it.
    private static let migrateToTwo = """
        BEGIN;
        ALTER TABLE records ADD COLUMN word_count INTEGER;
        CREATE TABLE mistakes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            record_id INTEGER NOT NULL,
            category TEXT NOT NULL,
            original TEXT NOT NULL,
            corrected TEXT NOT NULL,
            explanation TEXT NOT NULL
        );
        CREATE INDEX mistakes_record ON mistakes (record_id);
        CREATE TRIGGER records_delete_mistakes AFTER DELETE ON records
        BEGIN
            DELETE FROM mistakes WHERE record_id = old.id;
        END;
        PRAGMA user_version = 2;
        COMMIT;
        """

    private static let insertMistake = """
        INSERT INTO mistakes (record_id, category, original, corrected, explanation)
        VALUES (?1, ?2, ?3, ?4, ?5)
        """

    private static let selectCorrections = """
        SELECT id, created_at, source_language, word_count FROM records
        WHERE action = 'correct' AND word_count IS NOT NULL AND created_at >= ?1
        ORDER BY created_at, id
        """

    private static let selectMistakes = """
        SELECT mistakes.record_id, mistakes.category, mistakes.original, mistakes.corrected,
            mistakes.explanation
        FROM mistakes JOIN records ON records.id = mistakes.record_id
        WHERE records.action = 'correct' AND records.word_count IS NOT NULL
            AND records.created_at >= ?1
        ORDER BY mistakes.id
        """

    private static let insert = """
        INSERT INTO records (created_at, action, source_language, target_language,
            profile_id, model, source_bundle_id, source_app_name, source_text, result_text,
            word_count)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
        """

    private static let deleteBefore = "DELETE FROM records WHERE created_at < ?1"
    private static let countAll = "SELECT count(*) FROM records"

    /// Search calls `HistorySearch.contains` from inside SQLite, so `WHERE`
    /// and `LIMIT` both stay in the query (#68).
    static let containsFunction = "lingoswen_contains"

    /// The actions this build knows -- constants, not user data. A row with
    /// any other action is left out here, so it never shortens a page.
    private static let knownActions = Action.allCases
        .map { "'" + $0.rawValue + "'" }
        .joined(separator: ", ")

    private static let selectPage = """
        SELECT id, created_at, action, source_language, target_language, profile_id,
            model, source_bundle_id, source_app_name, source_text, result_text
        FROM records
        WHERE action IN (\(knownActions))
            AND (?1 IS NULL OR \(containsFunction)(source_text, ?1)
                OR \(containsFunction)(result_text, ?1))
            AND (?2 IS NULL OR created_at < ?2 OR (created_at = ?2 AND id < ?3))
        ORDER BY created_at DESC, id DESC LIMIT ?4
        """

    /// Opened `FULLMUTEX`, so SQLite serialises the connection itself; the
    /// store is used from the main actor (see `HistoryStore`).
    private let connection: OpaquePointer

    private init(connection: OpaquePointer) {
        self.connection = connection
    }

    deinit {
        sqlite3_close_v2(connection)
    }

    /// Validates and locks down the folder, then opens the file in it.
    public static func inApplicationSupport(locator: StorageLocator) throws -> SQLiteHistoryStore {
        let directory = locator.applicationSupportDirectory()
        try locator.prepare(directory)
        return try open(at: directory.appending(path: fileName))
    }

    /// Opens, or creates, the database at `url`. A file that is not a
    /// database fails here, not on the first insert.
    public static func open(at url: URL) throws -> SQLiteHistoryStore {
        let path = url.path(percentEncoded: false)
        try lockDown(path)
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(
            path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard let connection = handle else {
            throw HistoryStoreError.cannotOpen("SQLite could not allocate a connection")
        }
        if status != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(connection))
            sqlite3_close_v2(connection)
            throw HistoryStoreError.cannotOpen(message)
        }
        // Another program reading the file (the sqlite3 shell, a browser)
        // holds a lock; wait briefly for it rather than lose the record.
        sqlite3_busy_timeout(connection, busyTimeoutMilliseconds)
        // From here `deinit` closes the connection on every failure.
        let store = SQLiteHistoryStore(connection: connection)
        do {
            try store.configure()
        } catch HistoryStoreError.statementFailed(let message) {
            throw HistoryStoreError.cannotOpen(message)
        }
        try store.registerSearch()
        try excludeFromBackup(url)
        return store
    }

    /// The record and its mistakes in one transaction: never one without
    /// the other.
    public func add(_ record: HistoryRecord) throws -> Int64 {
        try execute("BEGIN")
        do {
            let id = try insertRecord(record)
            for mistake in record.mistakes {
                try insert(mistake, of: id)
            }
            try execute("COMMIT")
            return id
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func insertRecord(_ record: HistoryRecord) throws -> Int64 {
        let statement = try prepare(Self.insert)
        defer { sqlite3_finalize(statement) }
        if sqlite3_bind_double(statement, 1, record.date.timeIntervalSince1970) != SQLITE_OK {
            throw failure()
        }
        try bind(record.action.rawValue, 2, statement)
        try bind(record.sourceLanguage.rawValue, 3, statement)
        try bind(record.targetLanguage?.rawValue, 4, statement)
        try bind(record.profileID, 5, statement)
        try bind(record.model, 6, statement)
        try bind(record.sourceBundleID, 7, statement)
        try bind(record.sourceAppName, 8, statement)
        try bind(record.source.value, 9, statement)
        try bind(record.result.value, 10, statement)
        try bindWordCount(record.wordCount, statement)
        if sqlite3_step(statement) != SQLITE_DONE { throw failure() }
        return sqlite3_last_insert_rowid(connection)
    }

    private func insert(_ mistake: Mistake, of record: Int64) throws {
        let statement = try prepare(Self.insertMistake)
        defer { sqlite3_finalize(statement) }
        if sqlite3_bind_int64(statement, 1, record) != SQLITE_OK { throw failure() }
        try bind(mistake.category.rawValue, 2, statement)
        try bind(mistake.original.value, 3, statement)
        try bind(mistake.corrected.value, 4, statement)
        try bind(mistake.explanation.value, 5, statement)
        if sqlite3_step(statement) != SQLITE_DONE { throw failure() }
    }

    public func corrections(since date: Date) throws -> [CorrectionStats] {
        let mistakes = try mistakesByRecord(since: date)
        let statement = try prepare(Self.selectCorrections)
        defer { sqlite3_finalize(statement) }
        if sqlite3_bind_double(statement, 1, date.timeIntervalSince1970) != SQLITE_OK { throw failure() }
        var found: [CorrectionStats] = []
        while try step(statement) {
            let id = sqlite3_column_int64(statement, 0)
            found.append(CorrectionStats(
                date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                language: LanguageCode(Self.text(statement, 2) ?? ""),
                wordCount: Int(sqlite3_column_int64(statement, 3)),
                mistakes: mistakes[id] ?? []))
        }
        return found
    }

    /// A mistake whose category this build does not know counts as Other.
    private func mistakesByRecord(since date: Date) throws -> [Int64: [Mistake]] {
        let statement = try prepare(Self.selectMistakes)
        defer { sqlite3_finalize(statement) }
        if sqlite3_bind_double(statement, 1, date.timeIntervalSince1970) != SQLITE_OK { throw failure() }
        var found: [Int64: [Mistake]] = [:]
        while try step(statement) {
            let category = ErrorCategory(rawValue: Self.text(statement, 1) ?? "") ?? .other
            let mistake = Mistake(
                category: category,
                original: UserText(Self.text(statement, 2) ?? ""),
                corrected: UserText(Self.text(statement, 3) ?? ""),
                explanation: UserText(Self.text(statement, 4) ?? ""))
            found[sqlite3_column_int64(statement, 0), default: []].append(mistake)
        }
        return found
    }

    /// One step: true for a row, false when done, else the error. One place
    /// for the comparisons, so muter measures them: it places no mutant in
    /// a loop body inside a function that already has one. A mutant here
    /// cannot hang a `while`: a done statement either ends the loop or, if
    /// stepped again, restarts and then fails.
    private func step(_ statement: OpaquePointer) throws -> Bool {
        let status = sqlite3_step(statement)
        if status == SQLITE_ROW { return true }
        if status == SQLITE_DONE { return false }
        throw failure()
    }

    public func page(matching term: String?, before: HistoryCursor?, limit: Int) throws -> [HistoryRecord] {
        // SQLite reads a negative LIMIT as "no limit".
        if limit < 1 { return [] }
        let statement = try prepare(Self.selectPage)
        defer { sqlite3_finalize(statement) }
        // An unbound parameter is NULL: no cursor leaves ?2 and ?3 unbound.
        try bind(term, 1, statement)
        if let before {
            if sqlite3_bind_double(statement, 2, before.date.timeIntervalSince1970) != SQLITE_OK {
                throw failure()
            }
            if sqlite3_bind_int64(statement, 3, before.id) != SQLITE_OK { throw failure() }
        }
        if sqlite3_bind_int64(statement, 4, Int64(limit)) != SQLITE_OK { throw failure() }
        var records: [HistoryRecord] = []
        // Bounded by `limit` rather than "while there are rows": SQLite
        // restarts a finished statement on the next step, so a loop on the
        // step status alone runs forever once its test is inverted -- which
        // is exactly the mutant muter makes, and it hung CI (PR #105).
        for _ in 0..<limit {
            guard try step(statement) else { return records }
            if let record = Self.record(from: statement) {
                records.append(record)
            }
        }
        return records
    }

    /// `secure_delete` zeroes what is deleted; no `VACUUM`, as this runs
    /// after every save.
    public func deleteOlder(than date: Date) throws -> Int {
        let statement = try prepare(Self.deleteBefore)
        defer { sqlite3_finalize(statement) }
        // Bound directly: through a helper, CI's mutation toolchain stored
        // NULL (PR #106).
        if sqlite3_bind_double(statement, 1, date.timeIntervalSince1970) != SQLITE_OK {
            throw failure()
        }
        if sqlite3_step(statement) != SQLITE_DONE { throw failure() }
        return Int(sqlite3_changes(connection))
    }

    /// `secure_delete` zeroes the freed pages, then `VACUUM` rebuilds the
    /// file without them: nothing of the text remains in it (#69).
    public func deleteAll() throws {
        try execute("DELETE FROM records")
        try execute("VACUUM")
    }

    public func count() throws -> Int {
        let statement = try prepare(Self.countAll)
        defer { sqlite3_finalize(statement) }
        if sqlite3_step(statement) != SQLITE_ROW { throw failure() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    /// One `PRAGMA`'s value as text. Internal: tests read the settings here.
    func pragmaValue(_ name: String) throws -> String {
        let statement = try prepare("PRAGMA " + name)
        defer { sqlite3_finalize(statement) }
        if sqlite3_step(statement) != SQLITE_ROW { throw failure() }
        return Self.text(statement, 0) ?? ""
    }

    // MARK: - Opening

    /// Creates the file `0600` if it is missing, and sets `0600` either way:
    /// it is never readable by others, not even before SQLite opens it.
    private static func lockDown(_ path: String) throws {
        let files = FileManager.default
        if !files.fileExists(atPath: path) {
            let created = files.createFile(
                atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
            if !created { throw HistoryStoreError.cannotOpen("could not create the file") }
        }
        do {
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        } catch {
            throw HistoryStoreError.cannotOpen(error.localizedDescription)
        }
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var file = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try file.setResourceValues(values)
        } catch {
            throw HistoryStoreError.cannotOpen(error.localizedDescription)
        }
    }

    /// The version first: anything above 2 is a later version's file,
    /// refused before any setting can touch it (`journal_mode` rewrites the
    /// header). Then the settings, then the schema for a new file (0).
    private func configure() throws {
        let version = Int(try pragmaValue("user_version")) ?? 0
        if version > Self.schemaVersion { throw HistoryStoreError.newerSchema(version) }
        try execute("PRAGMA secure_delete = ON")
        try execute("PRAGMA journal_mode = DELETE")
        if version == 0 { try execute(Self.createSchema) }
        if version < Self.schemaVersion { try execute(Self.migrateToTwo) }
    }

    /// Registers `lingoswen_contains(text, term)`: 1 when `HistorySearch`
    /// finds the term in the text, 0 otherwise or for a NULL.
    private func registerSearch() throws {
        let status = sqlite3_create_function_v2(
            connection, Self.containsFunction, 2, SQLITE_UTF8 | SQLITE_DETERMINISTIC,
            nil, searchFunction, nil, nil, nil)
        if status != SQLITE_OK {
            throw HistoryStoreError.cannotOpen(String(cString: sqlite3_errmsg(connection)))
        }
    }

    // MARK: - Statements

    private func execute(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(connection, sql, nil, nil, &message)
        if status == SQLITE_OK { return }
        var text = "SQLite error \(status)"
        if let message { text = String(cString: message) }
        sqlite3_free(message)
        throw HistoryStoreError.statementFailed(text)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(connection, sql, -1, &statement, nil) != SQLITE_OK {
            sqlite3_finalize(statement)
            throw failure()
        }
        guard let statement else { throw failure() }
        return statement
    }

    private func failure() -> HistoryStoreError {
        .statementFailed(String(cString: sqlite3_errmsg(connection)))
    }

    /// SQLite copies the bytes (`SQLITE_TRANSIENT`), with an explicit length
    /// so a NUL inside the text is kept.
    /// Parameter 11 of `insert`; NULL for nil. Its own name, not a
    /// `bind` overload: an overload stored NULL under CI's mutation
    /// toolchain (PR #106). A function of its own, so muter measures it.
    private func bindWordCount(_ value: Int?, _ statement: OpaquePointer) throws {
        guard let value else { return }
        if sqlite3_bind_int64(statement, 11, Int64(value)) != SQLITE_OK { throw failure() }
    }

    private func bind(_ value: String?, _ index: Int32, _ statement: OpaquePointer) throws {
        var status = SQLITE_OK
        if let value {
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            status = sqlite3_bind_text(
                statement, index, value, Int32(value.utf8.count), transient)
        } else {
            status = sqlite3_bind_null(statement, index)
        }
        if status != SQLITE_OK { throw failure() }
    }

    // MARK: - Reading

    /// Nil for a row whose action this build does not know.
    private static func record(from statement: OpaquePointer) -> HistoryRecord? {
        guard let action = Action(rawValue: text(statement, 2) ?? "") else { return nil }
        var target: LanguageCode?
        if let code = text(statement, 4) { target = LanguageCode(code) }
        return HistoryRecord(
            id: sqlite3_column_int64(statement, 0),
            date: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            action: action,
            sourceLanguage: LanguageCode(text(statement, 3) ?? ""),
            targetLanguage: target,
            profileID: text(statement, 5),
            model: text(statement, 6) ?? "",
            sourceBundleID: text(statement, 7),
            sourceAppName: text(statement, 8),
            source: UserText(text(statement, 9) ?? ""),
            result: UserText(text(statement, 10) ?? ""))
    }

    /// Read by byte count, so a NUL inside the text is kept.
    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, column) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, column))
        return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
    }
}

/// `lingoswen_contains`, as SQLite calls it: a C function, so it captures
/// nothing and reads its two arguments by byte count.
private func searchFunction(
    _ context: OpaquePointer?, _ count: Int32, _ arguments: UnsafeMutablePointer<OpaquePointer?>?
) {
    var found: Int32 = 0
    if let arguments {
        if let text = searchArgument(arguments[0]) {
            if let term = searchArgument(arguments[1]) {
                if HistorySearch.contains(text, term) { found = 1 }
            }
        }
    }
    sqlite3_result_int(context, found)
}

private func searchArgument(_ value: OpaquePointer?) -> String? {
    guard let bytes = sqlite3_value_text(value) else { return nil }
    let count = Int(sqlite3_value_bytes(value))
    return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
}
