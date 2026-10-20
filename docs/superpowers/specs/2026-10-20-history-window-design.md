# Browse and search history — design

**Status:** approved in conversation 2026-10-20, pending review of this document.
**Milestone:** M3 Explain, Re-pitch & Polish. **Covers:** #68 (epic #12): a window that lists the records #67 keeps, newest first, filters them by a search term and copies a record's source or result. Retention, Clear All and turning history off (#69) are out of scope here.
**Parent spec:** `docs/superpowers/specs/2026-09-18-babelotter-design.md`, section 4.10 (`FR-HIS-02`) and section 4.8 (`FR-UI-02`). Builds on `docs/superpowers/specs/2026-10-19-history-record-design.md`.

## 1. What it does

- **History... in the menu.** A new menu item, above Check Again, opens the History window and brings lingoSwen to the front. Choosing it again brings the same window forward rather than opening a second one.
- **The list.** Records newest first. Each row shows the action, the languages, the time and the first line of the source. The first 200 load when the window opens; reaching the bottom loads the next 200, until there are no more.
- **Search.** A search field above the list. About 150 ms after typing stops, the list holds only the records whose source or result contains the term, ignoring case and accents: `uber` finds `Über`, `STRASSE` finds `strasse`, and `strasse` finds `Straße` (case folding turns `ß` into `ss`). An empty field (or one of only spaces) shows everything. Search covers the whole history, paged like the plain list.
- **The detail.** Selecting a record shows its full source and result, each selectable and with its own **Copy** button, and below them the audience, the source application, the model and the date and time. Copy writes the text as the popup's Copy does.
- **Live.** A record written while the window is open appears at the top without reopening; the selection stays on the record it was on.
- **When history is not saved.** If the database could not be opened, the window shows `History is not saved - <reason>` in place of the list. If reading fails, the window shows `Could not read the history - <reason>` and keeps what it had loaded.
- **Keyboard.** Command-W closes the window; Command-F focuses the search field; Command-C, Command-V, Command-X, Command-A and Command-Z work in the search field and the text views. lingoSwen has no main menu, so the window handles these itself.

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| How loose is matching | Case- and diacritic-insensitive, locale-independent (`String.range(of:options:)` with `.caseInsensitive` and `.diacriticInsensitive`) | What Finder and Mail do; SQLite's `LIKE` folds ASCII only, so `über` would miss `Über` |
| Where matching runs | One Swift function, `HistorySearch.matches`, used by both stores; SQLite calls it as a registered SQL function | The stores cannot disagree; `WHERE` and `LIMIT` stay inside SQLite, so the read loop stays bounded by `limit` (the hang of PR #105) |
| How the list pages | Keyset paging on (date, id), 200 at a time, one extra row fetched to know whether more exist | A record added at the top does not shift the next page; responsive however large the history grows |
| How live update works | `HistoryRecorder` notifies after a successful write; the window reloads from the top one more record than it had loaded | One code path, correct for a search too; every loaded record stays, so the selection does; a reload of a few hundred rows takes milliseconds |
| Where the list logic lives | `HistoryBrowser` in the kit | Paging, searching and reloading are tested and under the mutation gate; the app only displays them |
| Where row labels come from | `HistoryRow` in the kit, from a record and the current `Configuration` | Pure and tested; a deleted audience or language falls back to its id |
| The window | A plain `NSWindow` hosting SwiftUI, built once and kept | The app is an accessory (no Dock icon, no main menu); the popup's non-activating panel is the wrong kind of window for something you browse |
| Re-copy | The pasteboard write the popup's Copy uses (`concealed: false`) | Same behaviour as the user already knows; there is no restore because the copy is the point |

## 3. The kit (`Sources/BabelOtterKit/History/`)

### 3.1 `HistorySearch`

```swift
public enum HistorySearch {
    /// The term as search uses it: trimmed of white space; nil when nothing is left.
    public static func normalized(_ term: String) -> String?
    /// True when `text` contains `term`, ignoring case and accents, in any locale.
    public static func contains(_ text: String, _ term: String) -> Bool
    /// True when the record's source or result contains `term`.
    public static func matches(_ record: HistoryRecord, _ term: String) -> Bool
}
```

`contains` uses `range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: nil) != nil`. Only source and result text are searched, not the audience, app or model.

### 3.2 `HistoryCursor` and the store

```swift
/// Where a page ends: the last record's date and id.
public struct HistoryCursor: Sendable, Equatable {
    public let date: Date
    public let id: Int64
    public init(date: Date, id: Int64)
    /// Nil for a record no store has kept.
    public init?(_ record: HistoryRecord)
    /// True when `record` is strictly older; `InMemoryHistoryStore` filters with it.
    public func precedes(_ record: HistoryRecord) -> Bool
}

public protocol HistoryStore: AnyObject {
    func add(_ record: HistoryRecord) throws -> Int64
    /// Newest first (by date, then id), at most `limit`, strictly older than
    /// `before` when given, and only records matching `term` when given
    /// (`HistorySearch.matches`). None for a limit below 1. `term` is used as
    /// given; callers pass `HistorySearch.normalized`.
    func page(matching term: String?, before: HistoryCursor?, limit: Int) throws -> [HistoryRecord]
}

extension HistoryStore {
    /// The newest `limit` records.
    public func recent(limit: Int) throws -> [HistoryRecord]   // page(matching: nil, before: nil, limit:)
}
```

"Strictly older" means a date before the cursor's, or the same date and a lower id. `InMemoryHistoryStore` implements `page` by sorting, filtering with `HistorySearch.matches` and the cursor, and taking the prefix.

### 3.3 `SQLiteHistoryStore`

- At open, after `configure()`, registers `lingoswen_contains(text, term)` with `sqlite3_create_function_v2` (`SQLITE_UTF8 | SQLITE_DETERMINISTIC`, two arguments). The C callback reads both arguments by byte count, as the existing column reader does, and returns 1 or 0 from `HistorySearch.contains`. A NULL argument gives 0. A registration failure throws `.cannotOpen`.
- One statement for `page`, with every value bound:

  ```sql
  SELECT <columns> FROM records
  WHERE action IN (<every Action.rawValue>)
    AND (?1 IS NULL OR lingoswen_contains(source_text, ?1) OR lingoswen_contains(result_text, ?1))
    AND (?2 IS NULL OR created_at < ?2 OR (created_at = ?2 AND id < ?3))
  ORDER BY created_at DESC, id DESC LIMIT ?4
  ```

- The `IN` list is built once from `Action.allCases` (constants of this build, not user data), so a row with an unknown action is left out by SQLite and never counts against `limit`: a page holds exactly `limit` records whenever that many exist. The read loop stays `for _ in 0..<limit`, as in #67, and still skips a row it cannot read.
- The schema does not change (still version 1). No index is added: a search reads every row anyway, and a plain page reads at most 201 rows in `created_at` order. 5,000 records are within the manual check (6.2).

### 3.4 `HistoryBrowser`

```swift
/// What the History window shows, and how it pages (#68).
public final class HistoryBrowser {
    public static let pageSize = 200

    /// `store` is nil when history could not be opened; `unavailable` then says why.
    public init(store: (any HistoryStore)?, unavailable: String?, pageSize: Int = HistoryBrowser.pageSize)

    public private(set) var records: [HistoryRecord]
    /// The normalized term in force; nil shows everything.
    public private(set) var term: String?
    /// True while older records may exist.
    public private(set) var hasMore: Bool
    /// Worded to follow "History is not saved - " when the store is nil,
    /// or "Could not read the history - " after a failed read; nil otherwise.
    public private(set) var problem: HistoryBrowserProblem?

    /// Replaces the list with the first page for `term` (normalized). A term
    /// equal to the one in force does nothing.
    public func search(_ term: String)
    /// Appends the next page after the last record; does nothing when `hasMore` is false.
    public func loadMore()
    /// Reloads from the top one more record than are loaded (at least one page),
    /// for the term in force: a new record appears first and every loaded one stays.
    public func refresh()
}

public enum HistoryBrowserProblem: Equatable {
    case unavailable(String)   // the store could not be opened
    case reading(String)       // a page failed; what was loaded stays
}
```

- The constructor loads the first page.
- Each read asks for `n + 1` records and keeps `n`; `hasMore` is true when the extra one came back. The next page starts after the last record kept (`HistoryCursor(records.last)`).
- A successful read clears a `.reading` problem. A failed read sets `.reading(HistoryProblem.reading(error))` and leaves `records`, `term` and `hasMore` unchanged.
- With a nil store, every method does nothing and `problem` stays `.unavailable`.
- `HistoryProblem.reading(_:)` gives `could not read (<SQLite message>)`, in the style of `saving`.

### 3.5 `HistoryRow`

```swift
/// A record's labels, as the window shows them (#68).
public struct HistoryRow: Equatable {
    public let title: String        // Action.displayName
    public let languages: String    // see below
    public let audience: String?    // the profile's name, else its id; nil for Explain
    public let application: String? // sourceAppName, else sourceBundleID
    public let excerpt: String      // the source's first non-empty line, at most 80 characters, then "..."
    public init(_ record: HistoryRecord, configuration: Configuration)
}
```

`languages` is `<source> -> <target>` with a real arrow (`\u{2192}`, written as an escape: ASCII-only source), or just `<source>` when the target is nil. Each name is `configuration.language(for:)?.displayName`, falling back to the code. Dates are formatted in the app (`Date.formatted`), as they depend on the user's locale.

### 3.6 Mutation gate and constraints

`HistorySearch.swift`, `HistoryCursor.swift`, `HistoryBrowser.swift` and `HistoryRow.swift` join the PASS1 list in `.github/workflows/mutation.yml`. The constraints of #67 apply: ASCII only, no comma-joined conditions in `if`/`guard`/`while`, no ternary whose condition ends in an enum member, no UI import, no lock, and no loop whose only bound is a value read at run time.

## 4. The app

### 4.1 `HistoryRecorder`

- Keeps the store it opens and exposes it, with `problem`, for the browser: `var store: (any HistoryStore)?`.
- After a successful `add`, calls a new `onRecord` closure (separate from `onChange`, which is about the menu's problem line).

### 4.2 `HistoryWindowController`

- Owned by `AppDelegate`, created on first use; the window and its hosting controller are made once. The controller is the window's delegate and tracks open from `show()` to `windowWillClose`, so a minimized window counts as open. `show()` on a closed window gives the hosting controller a fresh `HistoryBrowser` and model; on an open one it only deminiaturizes and brings it forward. Either way it calls `NSApp.activate()`.
- `HistoryWindow: NSWindow`: titled, closable, resizable, miniaturizable; 820 x 520, minimum 600 x 360; centred the first time; `isReleasedWhenClosed = false`; frame autosaved as `HistoryWindow`. `performKeyEquivalent` handles exactly Command-W (close), Command-F (focus search), and Command-C/V/X/A/Z and Command-Shift-Z, sending `copy:`, `paste:`, `cut:`, `selectAll:`, `undo:` and `redo:` to the first responder; any other combination, and a key nobody takes, goes to `super`.
- `HistoryWindowModel: ObservableObject` wraps the browser and publishes `records`, `hasMore`, `problem` and `selection: Int64?` after each call. It debounces search by 150 ms, cancelling a pending search when typing resumes. It keeps the selection by id across `refresh()` and `loadMore()`, and clears it when a search removes that record.
- `onRecord` calls `refresh()` while the window is open, minimized included.

### 4.3 `HistoryView` (SwiftUI)

- `HSplitView`: on the left, a `List` of rows with the search field above it; on the right, the detail or "Select a record".
- Row: title and languages on the first line, the time on the right (`date.formatted(date: .abbreviated, time: .shortened)`), and the excerpt below in secondary colour.
- The last row's `onAppear` calls `loadMore()` when `hasMore`.
- Empty states: no records ("Nothing recorded yet."), no matches ("No records contain \"<term>\"."), `.unavailable` ("History is not saved - <reason>"). `.reading` shows as a line above the list, and the list stays.
- Detail: two sections, Source and Result, each a scrolling `Text` with `.textSelection(.enabled)` and a Copy button that shows "Copied" for a moment. Below them, a small grid: Audience, App, Model, Date.

### 4.4 The menu

`History...` (with a real ellipsis, written as an escape), above Check Again, always enabled: when history could not be opened, the window says why.

## 5. Out of scope

- Deleting a record, retention, Clear All, and turning history off (#69).
- Regenerate, Replace or "open in popup" from a record.
- Searching the audience, app or model; filtering by action or date.
- The Privacy panel's history line (#72).

## 6. Testing

### 6.1 Unit

- **`HistorySearchTests`**: case and diacritics are ignored (`uber` / `Über`, `ÉCOLE` / `école`); `strasse` matches `Straße` and the other way round; the result alone matches; the term is not matched against audience, app or model; `normalized` trims and gives nil for empty or white space; a Turkish dotless i behaves the same in any locale (`locale: nil`).
- **`HistoryStoreContractTests`** (both stores): `page` is newest first; `before` excludes the cursor's record and everything newer, including another record with the same date and a higher id; `matching` finds by source and by result, ignoring case and accents; `matching` and `before` combine; a limit below 1 gives none; `recent` equals `page(nil, nil, limit)`.
- **`SQLiteHistoryStoreTests`**: search with `%`, `_`, `'` and `\` in the term matches them literally; a NUL in the text is searched; an unknown-action row is left out and does not shorten a page.
- **`HistoryBrowserTests`** (`InMemoryHistoryStore`, page size 3): the first page loads in `init`; `hasMore` is true with 4 records and false with 3; `loadMore` appends without duplicates and stops; `search` replaces the list and resets paging; the same term twice reads once (a counting store); `refresh` after `add` puts the new record first and keeps every loaded record; a failed search leaves the old term in force; a last record without an id loads nothing more; a store that throws sets `.reading` and keeps the records, and the next good read clears it; a nil store gives `.unavailable` and every method is inert.
- **`HistoryRowTests`**: the languages line for each action; deleted audience and language fall back to their ids; Explain has no audience; the excerpt skips leading blank lines and cuts at 80 characters.

### 6.2 Manual (in HANDOFF)

Seed a large history first (quit lingoSwen; this adds 5,000 made-up records; they stay until #69's Clear All, or delete them with `delete from records where model = 'seed'`):

```sh
sqlite3 ~/Library/Application\ Support/ch.lingoswen/history.sqlite "with recursive n(i) as (select 1 union all select i + 1 from n where i < 5000) insert into records (created_at, action, source_language, target_language, profile_id, model, source_text, result_text) select strftime('%s','now') - i * 600, 'translate', 'en', 'de-CH', 'colleagues', 'seed', 'Seed record ' || i || ' about the Uber meeting', 'Testeintrag ' || i || ' zur Über-Sitzung' from n;"
```

| # | Do | Expect |
|---|---|---|
| W1 | Open the menu, choose History... | The window comes to the front, newest record first, each row with action, languages, time and first line |
| W2 | Scroll to the bottom repeatedly | More rows load each time; scrolling stays smooth; the oldest seed record (5000) is reached |
| W3 | Type `uber` in the search field | Only records containing "Uber" or "Über" are listed; clearing the field lists everything again |
| W4 | Select a record; press Copy under Result; paste in TextEdit | The detail shows source, result, audience, app, model and date; the result is pasted |
| W5 | Leave the window open, translate something and press Escape | The new record appears at the top; the selected record stays selected |
| W6 | Command-F, type, Command-A, Command-C, Command-V; select words in the Result text, Command-C, paste in TextEdit; then Command-W | Each works in the search field; the selected words are pasted; Command-W closes the window; History... opens it again at the same size |
| W7 | Quit; in `~/Library/Application Support/ch.lingoswen/`, `mv history.sqlite history.sqlite.keep && echo junk > history.sqlite`; start lingoSwen, choose History...; quit; `mv history.sqlite.keep history.sqlite` | The window shows "History is not saved - could not open the database (file is not a database)" |
| W8 | Search something, minimize the window; translate something and press Escape; choose History... | The window comes back with the search and selection kept, and the new record listed if it matches |
