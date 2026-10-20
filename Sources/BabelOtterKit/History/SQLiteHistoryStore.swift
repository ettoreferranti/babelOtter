import Foundation
import SQLite3

/// `HistoryStore` over the system SQLite library (#67, `FR-HIS-01`,
/// `FR-HIS-04`, `NFR-P7`).
///
/// The file is created `0600` before SQLite touches it and excluded from
/// backup. `secure_delete` overwrites deleted text and the rollback journal
/// leaves no `-wal` file holding it, so #69's Clear All needs no format
/// change. Every value is bound, never written into SQL.
public final class SQLiteHistoryStore: HistoryStore, @unchecked Sendable {

    public static let fileName = "history.sqlite"
    static let schemaVersion = 1

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

    private static let selectRecent = """
        SELECT id, created_at, action, source_language, target_language, profile_id,
            model, source_bundle_id, source_app_name, source_text, result_text
        FROM records ORDER BY created_at DESC, id DESC LIMIT ?1
        """

    /// The connection is a C pointer shared by every call; the lock is what
    /// makes the class `Sendable`.
    private let connection: OpaquePointer
    private let lock = NSLock()

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
        // From here `deinit` closes the connection on every failure.
        let store = SQLiteHistoryStore(connection: connection)
        do {
            try store.configure()
        } catch HistoryStoreError.statementFailed(let message) {
            throw HistoryStoreError.cannotOpen(message)
        }
        try excludeFromBackup(url)
        return store
    }

    public func add(_ record: HistoryRecord) throws -> Int64 {
        lock.lock()
        defer { lock.unlock() }
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
        if sqlite3_step(statement) != SQLITE_DONE { throw failure() }
        return sqlite3_last_insert_rowid(connection)
    }

    public func recent(limit: Int) throws -> [HistoryRecord] {
        // SQLite reads a negative LIMIT as "no limit".
        if limit < 1 { return [] }
        lock.lock()
        defer { lock.unlock() }
        let statement = try prepare(Self.selectRecent)
        defer { sqlite3_finalize(statement) }
        if sqlite3_bind_int64(statement, 1, Int64(limit)) != SQLITE_OK { throw failure() }
        var records: [HistoryRecord] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            if let record = Self.record(from: statement) {
                records.append(record)
            }
            status = sqlite3_step(statement)
        }
        if status != SQLITE_DONE { throw failure() }
        return records
    }

    /// One `PRAGMA`'s value as text. Internal: tests read the settings here.
    func pragmaValue(_ name: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
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

    /// Settings first, then the schema: 0 is a new file, 1 is current, and
    /// anything higher is a later version's file, refused untouched.
    private func configure() throws {
        try execute("PRAGMA secure_delete = ON")
        try execute("PRAGMA journal_mode = DELETE")
        let version = Int(try pragmaValue("user_version")) ?? 0
        if version > Self.schemaVersion { throw HistoryStoreError.newerSchema(version) }
        if version == 0 { try execute(Self.createSchema) }
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
