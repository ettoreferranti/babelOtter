# Record completed actions in a local database — design

**Status:** approved in conversation 2026-10-19, pending review of this document.
**Milestone:** M3 Explain, Re-pitch & Polish. **Covers:** #67 (epic #12): every completed action is kept in a local SQLite database, so a past result can be found again without regenerating it. Browsing and search (#68) and retention and Clear All (#69) build on this and are out of scope here.
**Parent spec:** `docs/superpowers/specs/2026-09-18-babelotter-design.md`, section 4.10 (`FR-HIS-01`, `FR-HIS-04`) and section 5.1 (`NFR-P5`, `NFR-P7`).

## 1. What it does

- **One record per popup.** When a popup closes, the most recent result that finished in it is recorded: source, result, action, languages, audience, model, time and source application. Regenerating, picking another audience or swapping replaces the pending record rather than adding one.
- **Nothing for what did not finish.** A popup closed before any run finished, or whose runs all failed, records nothing. A popup closed while a re-run is in flight records the earlier finished result.
- **Every way of closing counts.** Replace, Copy (after its pause), Escape or the close button, a new hotkey replacing the popup, and quitting the app each write the pending record, once.
- **Stored privately.** The database is `history.sqlite` in the application support folder that `StorageLocator` already validates (outside iCloud, folder `0700`, excluded from backup). The file itself is `0600` and excluded from backup.
- **Failure is visible, never fatal.** If the database cannot be opened, history is off for the session; if a write fails, that record is lost. Either way the menu shows `History: not saved - <reason>` and the app keeps working. No user text reaches a log or a message.

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| What is "a completed action" | The last finished result of a popup, written when it closes | One record per thing the user did; no near-duplicates from Regenerate; an Explain that was only read is still kept |
| Where SQLite lives | In the kit, behind a `HistoryStore` protocol | The test target depends on the kit only: SQLite code in the app would be untested and invisible to the mutation gate |
| SQLite access | System `libsqlite3` via `import SQLite3` | `FR-HIS` acceptance criterion; no dependency to allowlist (`NFR-P6`) |
| Journal and deletion | `journal_mode=DELETE`, `secure_delete=ON` from the first open | No `-wal` file holding text; #69's "no recoverable remnants" needs no format change |
| When the write happens | Synchronously on the main actor, at close | One insert takes well under a millisecond; a synchronous write cannot be lost to quitting |
| File permissions | The file is created `0600` before SQLite opens it | It is never readable by others, not even briefly |
| A database from a newer version | Refused (`.newerSchema`), history off | Altering a schema we do not know could destroy the user's records |
| Folder name | `BabelOtter.bundleIdentifier`, as for `config.json` | The folder is wherever the configuration already lives (today `ch.lingoswen`); the rename to `ch.babelotter` moves both together |

## 3. The kit (`Sources/BabelOtterKit/History/`)

### 3.1 `HistoryRecord`

```swift
public struct HistoryRecord: Sendable, Equatable {
    public var id: Int64?              // nil until stored
    public let date: Date
    public let action: Action
    public let sourceLanguage: LanguageCode
    public let targetLanguage: LanguageCode?
    public let profileID: String?
    public let model: String
    public let sourceBundleID: String?
    public let sourceAppName: String?
    public let source: UserText
    public let result: UserText
}
```

The memberwise `public init` with every field, plus one constructor per action. Each takes `model: String`, `application: SourceApplication?` and `date: Date`; the application fills `sourceBundleID` and `sourceAppName` (both nil when nil).

| Constructor | `sourceLanguage` | `targetLanguage` | `profileID` | `source` | `result` |
|---|---|---|---|---|---|
| `init(translation: TranslationResult, source: UserText, ...)` | `direction.source` | `direction.target` | `audience.id` | `source` | `text` |
| `init(repitch: TranslationResult, source: UserText, ...)` | `direction.source` | nil | `audience.id` | `source` | `text` |
| `init(correction: CorrectionResult, language: LanguageCode, profileID: String, ...)` | `language` | nil | `profileID` | `original` | `corrected` |
| `init(explanation: ExplanationResult, source: UserText, language: LanguageCode, ...)` | `language` | `en` | nil | `source` | `copyText` |

`description` and the mirror stay redacted because `source` and `result` are `UserText`.

### 3.2 `Configuration.model(for:)`

`public func model(for action: Action) -> String`: `models[action] ?? Configuration.defaultModel`. `Translator`, `Corrector`, `Explainer` and `ReadinessMonitor` use it instead of their own lookup, so the recorded model is by construction the one used.

### 3.3 `HistoryStore`

```swift
public protocol HistoryStore: Sendable {
    /// Stores the record and returns its new id. The record's own `id` is ignored.
    func add(_ record: HistoryRecord) throws -> Int64
    /// Newest first (by date, then id), at most `limit`.
    func recent(limit: Int) throws -> [HistoryRecord]
}

public enum HistoryStoreError: Error, Equatable {
    case cannotOpen(String)        // SQLite's or the file system's message
    case statementFailed(String)   // SQLite's message
    case newerSchema(Int)          // the file's user_version
}
```

No error carries record text. `InMemoryHistoryStore` (a `final class`, `Sendable` behind a lock) implements the protocol for tests.

### 3.4 `SQLiteHistoryStore`

- `public static func inApplicationSupport(locator: StorageLocator) throws -> SQLiteHistoryStore`: `locator.prepare` on the folder, then `open(at: folder/history.sqlite)`.
- `public static func open(at url: URL) throws -> SQLiteHistoryStore`:
  1. If the file does not exist, create it empty with permissions `0600`. In every case, set `0600` on it.
  2. `sqlite3_open_v2` with `SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX`; then `PRAGMA secure_delete=ON`, `PRAGMA journal_mode=DELETE`.
  3. Read `PRAGMA user_version`: 0 creates schema 1 and sets it to 1; 1 is used as is; anything higher throws `.newerSchema(n)` and closes.
  4. Mark the file excluded from backup.
  Any failure in these steps throws `.cannotOpen(message)` (or `.newerSchema`) and leaves no open connection. A file that is not a database fails here, not on the first insert.
- Schema 1:

  ```sql
  CREATE TABLE records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      created_at REAL NOT NULL,          -- seconds since 1970
      action TEXT NOT NULL,              -- Action.rawValue
      source_language TEXT NOT NULL,
      target_language TEXT,
      profile_id TEXT,
      model TEXT NOT NULL,
      source_bundle_id TEXT,
      source_app_name TEXT,
      source_text TEXT NOT NULL,
      result_text TEXT NOT NULL
  );
  ```

- Every statement is prepared, values are bound (text with `SQLITE_TRANSIENT`), never interpolated into SQL.
- A row whose `action` is not a known `Action` is skipped by `recent`, not a crash.
- `final class`, `@unchecked Sendable`: the connection is guarded by a lock; `deinit` closes it.

### 3.5 Mutation gate and constraints

The three new files join the PASS1 list in `.github/workflows/mutation.yml`. ASCII only, no comma-joined conditions in `if`/`guard`/`while`, no ternary whose condition ends in an enum member, no UI import.

## 4. The app

### 4.1 Opening the store

`AppDelegate` opens the store once at launch with the same `StorageLocator` that `ConfigurationSource` builds (the locator moves to one shared place). The result is `HistoryStore?` plus a problem string; it is passed into each popup alongside the `AppEnvironment` and survives configuration reloads.

### 4.2 `PopupModel`

- `pendingRecord: HistoryRecord?`, set on each `.finished` event from the matching constructor (3.1), with `configuration.model(for: action)`, the snapshot's application and `Date()`. Correct and Explain take the enabled German language's code; Explain falls back to `de-CH` exactly as `Explainer` does. Starting a run does not clear it; failing a run does not clear it.
- `recordHistory()`: writes `pendingRecord` once (a `recorded` flag), then sets it to nil. Called from the one place every close goes through, and from the app's termination handler for an open popup.
- A write error is handed to the app's problem reporting (4.3); the popup is not affected.

### 4.3 Menu

`History: not saved - <reason>` appears in the menu's problem section when opening failed or the last write failed, and goes away after the next successful write. The reason is the error's message: `could not open the database (<SQLite message>)`, `the database was written by a newer babelOtter (version <n>)`, or `could not save (<SQLite message>)`.

## 5. Testing

### 5.1 Unit

- **`HistoryStoreContractTests`**, each case run against `InMemoryHistoryStore` and a `SQLiteHistoryStore` in a temporary folder: every field round-trips, including nil optionals and text with `ß`, emoji, quotes, `'); DROP TABLE records; --` and line breaks; `recent` is newest first and honours `limit`; ids increase; `add` ignores the record's own `id`.
- **`SQLiteHistoryStoreTests`**: the file is `0600` after open, also when it existed with `0644`; it is excluded from backup; `secure_delete` is 1 and `journal_mode` is `delete`; records survive closing and reopening; `user_version` is 1; a file with `user_version` 2 throws `.newerSchema(2)`; a file of non-database bytes throws `.cannotOpen`; a row with an unknown action is skipped; `inApplicationSupport` refuses an iCloud-synced home folder.
- **`HistoryRecordTests`**: one test per constructor for languages, profile, source and result; Explain stores `copyText`; a nil application gives nil app fields; `String(describing:)` of a record contains no source or result text.
- **`ConfigurationTests`**: `model(for:)` returns the configured model, and the default when none is set.

### 5.2 Manual (in HANDOFF)

Inspect with `sqlite3 ~/Library/Application\ Support/ch.lingoswen/history.sqlite 'select action, source_language, target_language, profile_id, model, source_app_name, substr(result_text,1,40) from records order by id desc limit 5'`.

- **H1.** Translate, Regenerate, then Escape: exactly one new row, holding the second result.
- **H2.** Escape during the first run: no new row. Translate a non-configured language (refused): no new row.
- **H3.** Replace, Copy and Explain-then-close each add one row; quitting from the menu with a finished popup open adds its row.
- **H4.** `ls -l` shows `-rw-------` for `history.sqlite`; no `history.sqlite-wal` exists.

## 6. Out of scope

- The history window, search and re-copy (#68).
- Retention, Clear All and `VACUUM` (#69).
- The Privacy panel's history line (#73).
- Recording which result was used (Replace or Copy) or the per-run warnings.
