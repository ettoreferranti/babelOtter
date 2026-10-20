# History retention, off and Clear All — design

**Status:** approved in conversation 2026-10-20, pending review of this document.
**Milestone:** M3 Explain, Re-pitch & Polish. **Covers:** #69 (epic #12): records older than a configured period are deleted, history can be turned off, and Clear All deletes every record with no remnant in the database file. This completes epic #12.
**Parent spec:** `docs/superpowers/specs/2026-09-18-babelotter-design.md`, section 4.10 (`FR-HIS-03`) and section 5.1 (`NFR-P7`). Builds on the specs for #67 (`2026-10-19-history-record-design.md`) and #68 (`2026-10-20-history-window-design.md`).

## 1. What it does

- **One setting.** `retentionDays` in `config.json` takes a whole number of days (1 or more), `"unlimited"` or `"off"`. The default stays `90`. The words are read trimmed and case-insensitively. Anything else (`0`, `-5`, `1.5`, `"never"`, `null`) is a configuration problem: `retentionDays: expected a number of days (1 or more), "unlimited" or "off"`.
- **Old records go.** With a number of days, records older than that are deleted at launch, when a saved change to the setting is applied, and after each record is saved, so the limit also holds while lingoSwen runs for weeks. With `"unlimited"` or `"off"`, nothing is deleted.
- **Off records nothing.** With `"off"`, a closing popup writes no record. Existing records stay until Clear All. The menu shows `History: off` above History..., as information that does not change the menu-bar icon. The History window still lists the existing records, under the line `History is off - nothing new is saved.`
- **A broken file pauses history.** When lingoSwen started on the defaults because `config.json` could not be read (malformed, or present but unreadable: no permission, a folder of that name, an I/O error) or its folder could not be prepared, it cannot know the retention you chose, so it records and deletes nothing. The menu shows `History: off until config.json is fixed`. A typo can therefore never turn recording back on. A problem found later, mid-session, keeps the previous settings (#26) and with them the retention in force. A first launch with no file is not a problem: the defaults are real, and 90 days applies.
- **Clear All.** A Clear All... button in the History window asks `Delete all <n> records? This cannot be undone.` with Delete (destructive) and Cancel (Escape). Delete removes every record at once, then the file is rebuilt so nothing of the deleted text remains in it. The window then reloads, also when the rebuild failed after the rows were deleted, so no deleted record stays listed. A popup still open during Clear All holds a result from before it; that result is not recorded afterwards. The button is disabled when history could not be opened, or when the list is empty with no search and no failed read. Switching to off or paused also clears an earlier "not saved" line, since nothing is written then.
- **Failures are visible.** A failed deletion of old records shows `History: old records not deleted - <reason>` in the menu; a failed Clear All shows `Could not clear the history - <reason>` in the window, and the records stay listed.

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| How off and unlimited are written | The same key, a number or a word | Existing files keep working; one key to find; no magic numbers |
| When old records are deleted | Launch, applied setting change, each saved record | The criterion asks for launch; a menu-bar app can run for weeks; one bounded `DELETE` per save needs no timer |
| What a broken file does | Records and deletes nothing until it reads cleanly | Defaults record for 90 days; falling back to them would let a typo undo "off". Deleting nothing protects a user who chose "unlimited" |
| Where Clear All lives | The History window only, with a confirmation naming the count | What the criterion describes; you see what you are deleting; no destructive item in the everyday menu |
| No recoverable remnants | `DELETE FROM records` with `secure_delete` (already on), then `VACUUM` | `secure_delete` zeroes the freed pages; `VACUUM` rebuilds the file without them, so the file is small and holds no trace. A test reads the raw bytes |
| Off and existing records | Kept until Clear All | The criterion; turning recording off should not destroy what you may still need |
| Where the rules live | `HistoryRetention` and `HistoryPolicy` in the kit | Parsing and the record/prune decisions are tested and under the mutation gate |

## 3. The kit

### 3.1 `HistoryRetention` (`Sources/BabelOtterKit/Config/HistoryRetention.swift`)

```swift
public enum HistoryRetention: Sendable, Equatable, Codable {
    case days(Int)      // 1 or more
    case unlimited
    case off

    public static let `default` = HistoryRetention.days(90)
    /// The records older than this are deleted; nil for .unlimited and .off.
    public func cutoff(now: Date) -> Date?
}
```

- Decoding (single value): an integer of 1 or more is `.days`; a string that, trimmed and lowercased, is `unlimited` or `off` is that case. Anything else throws `DecodingError.dataCorrupted` with the debug description `expected a number of days (1 or more), "unlimited" or "off"`, which `ConfigurationStore` already turns into the field-named problem.
- Encoding: `.days(n)` as the number `n`, the others as `"unlimited"` and `"off"`. The default file still reads `"retentionDays" : 90`.
- `cutoff(now:)` is `now` minus `n * 86_400` seconds. Calendar days and time zones do not matter at this resolution.
- `Configuration.retentionDays` changes type from `Int` to `HistoryRetention`; the key and its default are unchanged.

### 3.2 `HistoryPolicy` (`Sources/BabelOtterKit/History/HistoryPolicy.swift`)

```swift
/// What history does under the configuration in use (#69).
public enum HistoryPolicy: Equatable, Sendable {
    case keep(HistoryRetention)   // .days or .unlimited: record, and prune for .days
    case off                      // the user's "off": record nothing, delete nothing
    case paused                   // the configuration is a fallback: record nothing, delete nothing

    public init(retention: HistoryRetention, configurationIsFallback: Bool)
    public var records: Bool
    /// The cutoff for pruning now; nil when nothing may be deleted.
    public func pruneCutoff(now: Date) -> Date?
    /// The menu's information line; nil while recording.
    public var menuNote: String?      // "History: off", "History: off until config.json is fixed"
    /// The window's line above the list; nil while recording.
    public var windowNote: String?    // "History is off - nothing new is saved.", "History is off until config.json is fixed - nothing new is saved."
}
```

`configurationIsFallback` wins over the retention: a fallback configuration is `.paused` whatever it says.

### 3.3 The store

```swift
public protocol HistoryStore: AnyObject {
    ...
    /// Deletes every record dated before `date`; returns how many.
    func deleteOlder(than date: Date) throws -> Int
    /// Deletes every record and leaves no trace of them in storage.
    func deleteAll() throws
    /// How many records there are, for Clear All's confirmation.
    func count() throws -> Int
}
```

- `SQLiteHistoryStore.deleteOlder`: `DELETE FROM records WHERE created_at < ?1`, bound with `sqlite3_bind_double` called directly (the form CI's mutation toolchain is known to compile correctly, PR #106); returns `sqlite3_changes`. No `VACUUM`: `secure_delete` already zeroes what was deleted, and a rebuild after every save would be wasteful.
- `deleteAll`: `DELETE FROM records`, then `VACUUM`. `secure_delete` zeroes the freed pages first; `VACUUM` then rebuilds the file at its minimum size.
- `count`: `SELECT count(*) FROM records`.
- `InMemoryHistoryStore` implements all three.
- Known limit, stated in `PRIVACY.md`: during a delete, SQLite's rollback journal (`history.sqlite-journal`) briefly holds the old pages and is removed at commit without being overwritten. The database file holds no remnant; the removed journal's disk blocks are protected by FileVault, not by lingoSwen.

### 3.4 `HistoryProblem` and the browser

- `HistoryProblem.pruning(_:)`: `old records not deleted (<SQLite message>)`, shown as `History: old records not deleted - ...`. To allow that, the readiness cause `.historyProblem` carries the whole line rather than the part after `History: not saved - `; `HistoryProblem.opening` and `saving` return the whole line too (`not saved - could not open the database (...)`), and existing tests are updated with the same wording.
- `HistoryProblem.clearing(_:)`: `could not clear (<SQLite message>)`, shown in the window as `Could not clear the history - ...`.
- `HistoryBrowser.clearAll() -> Bool`: calls `deleteAll`, then reloads (an empty list). A failure sets `problem = .clearing(...)` and keeps the records. `HistoryBrowser.count() -> Int?` for the confirmation. `HistoryBrowserProblem` gains `.clearing(String)`.

### 3.5 Mutation gate and constraints

`HistoryRetention.swift` and `HistoryPolicy.swift` join the PASS1 list. The constraints of #67 and #68 apply: ASCII only, no comma-joined conditions, no ternary ending in an enum member, no UI import, no lock, no loop bounded only by a run-time value.

## 4. The app

### 4.1 `ConfigurationSource`

`isFallback: Bool`: true when the launch load had problems (the defaults are in use because the file could not be read) or the folder could not be prepared. A first launch with no file is false. A reload that reads cleanly sets it false; a reload with problems leaves it as it was (the previous configuration stays in use, #26).

### 4.2 `HistoryRecorder`

- `policy: HistoryPolicy`, set by `AppDelegate` from `HistoryPolicy(retention: source.configuration.retentionDays, configurationIsFallback: source.isFallback)` at launch and after each reload.
- `record(_:)` writes nothing unless `policy.records`. After a successful write it prunes.
- `prune()`: when `policy.pruneCutoff(now: Date())` is not nil, `deleteOlder(than:)`. Called at launch, when the policy changes, and after each write. A failure sets `problem` to the pruning line; the next successful prune or write clears a pruning problem.
- `onRecord` also fires after a prune that deleted something, so an open window drops the deleted records.

### 4.3 The menu

The `History: off` or `History: off until config.json is fixed` line is a section header directly above History..., present only while not recording. It is not a readiness cause, so the icon stays as it is.

### 4.4 The window

- The note line from `policy.windowNote` sits above the list when present; the window's model reads the policy from the recorder when it opens and when `onRecord` or a policy change fires.
- A Clear All... button at the bottom of the list column. It opens an `NSAlert` as a sheet on the window: message `Delete all <n> records?`, informative text `This cannot be undone.`, buttons Delete (`hasDestructiveAction`, default) and Cancel (key equivalent Escape). Delete calls `clearAll()`; the selection is cleared.
- The button is disabled while the list is empty with no term in force, and when the problem is `.unavailable`.

## 5. Out of scope

- Deleting a single record.
- A settings window for retention (the settings epic).
- Overwriting the removed journal's disk blocks.
- The Privacy panel's history line (#72).

## 6. Testing

### 6.1 Unit

- **`HistoryRetentionTests`**: `90`, `1`, `"unlimited"`, `" Off "`, `"UNLIMITED"` decode; `0`, `-5`, `1.5`, `"never"`, `""`, `null`, `true` fail with the message; encoding gives `90`, `"unlimited"`, `"off"`; round trip; `cutoff` for `.days(1)` is exactly 86,400 s before `now`, nil for the others.
- **`ConfigurationStoreTests`**: a file with `"retentionDays" : "off"` loads as `.off`; one with `"retentionDays" : 0` reports the problem on the field `retentionDays`; the default file still has `"retentionDays" : 90`.
- **`HistoryPolicyTests`**: each retention with and without fallback; `records`; `pruneCutoff` only for `.keep(.days)`; the notes' wording.
- **Contract tests (both stores)**: `deleteOlder` deletes strictly older records and returns the count, keeping one dated exactly at the cutoff; `deleteAll` leaves none and `count` is 0; `count` counts.
- **`SQLiteHistoryStoreTests`**: after adding records with a distinctive text and calling `deleteAll`, the raw bytes of `history.sqlite` do not contain that text (UTF-8), and the file is no larger than a fresh one plus a page; after `deleteOlder`, the deleted record's text is not in the raw bytes either (`secure_delete`).
- **`HistoryBrowserTests`**: `clearAll` empties the list and `hasMore` is false; a failing store sets `.clearing` and keeps the records; `count`.
- **`HistoryProblemTests`** and **`ReadinessPolicyTests`**: the whole-line wording.

### 6.2 Manual (in HANDOFF)

| # | Do | Expect |
|---|---|---|
| C1 | Seed the 5,000 records (#68's command); open History; press Clear All..., then Cancel; then Clear All... and Delete | The alert names 5,000 and more; Cancel keeps everything; Delete empties the list at once; `ls -l` shows a small `history.sqlite` and no `-journal` |
| C2 | Set `"retentionDays" : "off"` and save; open the menu; translate something and press Escape; open History | The menu shows "History: off" and the icon is unchanged; no new record; the window says "History is off - nothing new is saved." and lists the old records |
| C3 | Set `"retentionDays" : 1`; quit; insert a record dated two days ago (`sqlite3 ... "insert into records (created_at, action, source_language, model, source_text, result_text) values (strftime('%s','now') - 172800, 'translate', 'en', 'm', 'old', 'old')"`); start lingoSwen; open History | The old record is gone; today's records are listed |
| C4 | Quit; break the file (`"retentionDays" : "nope"`); start lingoSwen; translate and press Escape; fix the file and save; translate and press Escape | The menu shows the config.json problem and "History: off until config.json is fixed"; no row is added; after the fix, the line goes and the next translation is recorded |
| C5 | Set `"retentionDays" : "unlimited"`; restart | Nothing is deleted; the menu has no history line |
