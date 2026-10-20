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
    static let schemaVersion = 1
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

    private static let insert = """
        INSERT INTO records (created_at, action, source_language, target_language,
            profile_id, model, source_bundle_id, source_app_name, source_text, result_text)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
        """

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

    public func add(_ record: HistoryRecord) throws -> Int64 {
        let statement = try prepare(Self.insert)
        defer { sqlite3_finalize(statement) }
        try bind(record.date.timeIntervalSince1970, 1, statement)
        try bind(record.action.rawValue, 2, statement)
        try bind(record.sourceLanguage.rawValue, 3, statement)
        try bind(record.targetLanguage?.rawValue, 4, statement)
        try bind(record.profileID, 5, statement)
        try bind(record.model, 6, statement)
        try bind(record.sourceBundleID, 7, statement)
        try bind(record.sourceAppName, 8, statement)
        try bind(record.source.value, 9, statement)
        try bind(record.result.value, 10, statement)
        if sqlite3_step(statement) != SQLITE_DONE { throw failure() }
        return sqlite3_last_insert_rowid(connection)
    }

    public func page(matching term: String?, before: HistoryCursor?, limit: Int) throws -> [HistoryRecord] {
        // SQLite reads a negative LIMIT as "no limit".
        if limit < 1 { return [] }
        let statement = try prepare(Self.selectPage)
        defer { sqlite3_finalize(statement) }
        // An unbound parameter is NULL: no cursor leaves ?2 and ?3 unbound.
        try bind(term, 1, statement)
        if let before {
            try bind(before.date.timeIntervalSince1970, 2, statement)
            if sqlite3_bind_int64(statement, 3, before.id) != SQLITE_OK { throw failure() }
        }
        if sqlite3_bind_int64(statement, 4, Int64(limit)) != SQLITE_OK { throw failure() }
        var records: [HistoryRecord] = []
        // Bounded by `limit` rather than "while there are rows": SQLite
        // restarts a finished statement on the next step, so a loop on the
        // step status alone runs forever once its test is inverted -- which
        // is exactly the mutant muter makes, and it hung CI (PR #105).
        for _ in 0..<limit {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return records }
            if status != SQLITE_ROW { throw failure() }
            if let record = Self.record(from: statement) {
                records.append(record)
            }
        }
        return records
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

    /// The version first: anything above 1 is a later version's file,
    /// refused before any setting can touch it (`journal_mode` rewrites the
    /// header). Then the settings, then the schema for a new file (0).
    private func configure() throws {
        let version = Int(try pragmaValue("user_version")) ?? 0
        if version > Self.schemaVersion { throw HistoryStoreError.newerSchema(version) }
        try execute("PRAGMA secure_delete = ON")
        try execute("PRAGMA journal_mode = DELETE")
        if version == 0 { try execute(Self.createSchema) }
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

    private func bind(_ value: Double, _ index: Int32, _ statement: OpaquePointer) throws {
        if sqlite3_bind_double(statement, index, value) != SQLITE_OK { throw failure() }
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
