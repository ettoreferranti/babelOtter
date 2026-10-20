# Record Completed Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every popup's last finished result is written, when the popup closes, to a private local SQLite database (#67).

**Architecture:** The kit gains `History/`: a `HistoryRecord` value with one constructor per action, a `HistoryStore` protocol with an in-memory and a system-`libsqlite3` implementation, and the wording of history problems. Readiness gains a `historyProblem` cause for the menu. The app opens the store once at launch and `PopupModel` keeps a pending record that it writes once on every way out.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing, `import SQLite3` (system library), Foundation.

**Spec:** `docs/superpowers/specs/2026-10-19-history-record-design.md`

## Global Constraints

- Kit sources (`Sources/BabelOtterKit`): ASCII only (`\u{...}` escapes), no UI imports, no comma-joined conditions in `if`/`guard`/`while`, no ternary whose condition ends in an enum member, no closures holding logic that should be mutation-tested (use named functions).
- Every new kit file joins the PASS1 list in `.github/workflows/mutation.yml` (the CI guard fails on any unlisted kit file).
- No package dependency. SQLite is `import SQLite3`.
- No user text in any log, error or message. Errors carry SQLite's or the file system's message only.
- The database file is `history.sqlite` in `StorageLocator.applicationSupportDirectory()`, mode `0600`, excluded from backup; `secure_delete=ON`, `journal_mode=DELETE`; schema version 1 in `PRAGMA user_version`.
- Menu wording: `History: not saved - <reason>`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Test commands: `swift test --filter <Suite> 2>&1 | tail -20`; full suite `swift test 2>&1 | tail -5`.

## Review Focus

1. Text with an embedded NUL or of 100 000 characters must come back byte for byte (`bind_text` with an explicit byte length, column read by byte count) -- pinned in Task 3/4 contract tests.
2. Two records with the same date must come back newest-id first, in both stores -- pinned in the contract tests.
3. A Replace that fails (popup reopens with a message) and is then dismissed must record exactly once -- manual check H3.
4. A store that cannot be opened (folder refused, non-database file, newer schema) must leave every action working and show one menu line -- `HistoryProblem` tests in Task 5 and manual check H5.
5. `recent(limit:)` with `limit` 0 or negative must return nothing in both stores (SQLite treats a negative LIMIT as "no limit") -- pinned in the contract tests.

---

### Task 1: Configuration helpers for the model and the German language

**Files:**
- Modify: `Sources/BabelOtterKit/Config/Configuration.swift` (add an extension at the end)
- Modify: `Sources/BabelOtterKit/Pipeline/Translator.swift:258`, `Sources/BabelOtterKit/Pipeline/Corrector.swift:96-99,110`, `Sources/BabelOtterKit/Pipeline/Explainer.swift:97-99`
- Modify: `Sources/BabelOtterApp/ReadinessMonitor.swift:49`
- Test: `Tests/BabelOtterKitTests/Config/ConfigurationTests.swift` (new)

**Interfaces:**
- Produces: `Configuration.model(for action: Action) -> String`; `Configuration.germanLanguage: LanguageConfig`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing

@testable import BabelOtterKit

@Suite("Configuration answers which model and which German")
struct ConfigurationTests {

    @Test("a configured model is the one an action uses")
    func configuredModel() {
        var configuration = Configuration.default
        configuration.models[.explain] = "llama3.1:8b"
        #expect(configuration.model(for: .explain) == "llama3.1:8b")
        #expect(configuration.model(for: .translate) == Configuration.defaultModel)
    }

    @Test("an action with no configured model uses the default")
    func defaultModel() {
        var configuration = Configuration.default
        configuration.models = [:]
        #expect(configuration.model(for: .correct) == Configuration.defaultModel)
    }

    @Test("German is the enabled German language, whatever its region")
    func enabledGerman() {
        var configuration = Configuration.default
        let german = LanguageConfig(
            code: LanguageCode("de-DE"), displayName: "German", localeRules: [], enabled: true)
        configuration.languages = [.english, german]
        #expect(configuration.germanLanguage == german)
    }

    @Test("with no German enabled, German is Swiss Standard German")
    func fallbackGerman() {
        var configuration = Configuration.default
        let german = LanguageConfig(
            code: LanguageCode("de-AT"), displayName: "Austrian", localeRules: [], enabled: false)
        configuration.languages = [.english, german]
        #expect(configuration.germanLanguage == .swissGerman)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --filter ConfigurationTests 2>&1 | tail -20`
Expected: build FAILS with "value of type 'Configuration' has no member 'model'" and "no member 'germanLanguage'".

- [ ] **Step 3: Implement**

Append to `Sources/BabelOtterKit/Config/Configuration.swift`:

```swift
extension Configuration {

    /// The model `action` runs on: the configured one, else the default.
    /// The pipelines and history both ask here, so a recorded model is by
    /// construction the one that produced the result (#67).
    public func model(for action: Action) -> String {
        models[action] ?? Configuration.defaultModel
    }

    /// The enabled German language, whatever its region, so its locale rules
    /// (ss for de-CH) apply; Swiss Standard German, the shipped default,
    /// when none is enabled. Correct and Explain read German.
    public var germanLanguage: LanguageConfig {
        enabledLanguages.first(where: Self.isGerman) ?? .swissGerman
    }

    private static func isGerman(_ language: LanguageConfig) -> Bool {
        language.code.baseSubtag == LanguageCode("de")
    }
}
```

Then replace the lookups:
- `Translator.swift:258`: `model: configuration.models[action] ?? Configuration.defaultModel,` becomes `model: configuration.model(for: action),`
- `Corrector.swift`: the `germanLanguage` property body becomes `configuration.germanLanguage`; line 110 becomes `model: configuration.model(for: .correct),`
- `Explainer.swift:97-99`: `german: language(Self.german, or: .swissGerman)` becomes `german: configuration.germanLanguage`; `model: configuration.models[.explain] ?? Configuration.defaultModel` becomes `model: configuration.model(for: .explain)`. Keep `language(_:or:)` for English.
- `ReadinessMonitor.swift:49`: `models[action] = configuration.model(for: action)`.

- [ ] **Step 4: Run the tests to see them pass, then the whole suite**

Run: `swift test --filter ConfigurationTests 2>&1 | tail -20`
Expected: 4 tests pass.
Run: `swift test 2>&1 | tail -5`
Expected: all tests pass (777 + 4).

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterKit/Config/Configuration.swift Sources/BabelOtterKit/Pipeline Sources/BabelOtterApp/ReadinessMonitor.swift Tests/BabelOtterKitTests/Config/ConfigurationTests.swift
git commit -m "refactor(config): one place answers which model and which German (#67)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `HistoryRecord`

**Files:**
- Create: `Sources/BabelOtterKit/History/HistoryRecord.swift`
- Modify: `.github/workflows/mutation.yml` (PASS1 list)
- Test: `Tests/BabelOtterKitTests/History/HistoryRecordTests.swift`, `Tests/BabelOtterKitTests/History/HistoryFixtures.swift`

**Interfaces:**
- Consumes: `TranslationResult`, `CorrectionResult`, `ExplanationResult` (memberwise initialisers visible through `@testable import`), `SourceApplication`.
- Produces:
  - `public struct HistoryRecord: Sendable, Equatable` with `var id: Int64?`, `let date: Date`, `let action: Action`, `let sourceLanguage: LanguageCode`, `let targetLanguage: LanguageCode?`, `let profileID: String?`, `let model: String`, `let sourceBundleID: String?`, `let sourceAppName: String?`, `let source: UserText`, `let result: UserText`; `public init(id:date:action:sourceLanguage:targetLanguage:profileID:model:sourceBundleID:sourceAppName:source:result:)` with `id: Int64? = nil` first.
  - `init(translation: TranslationResult, source: UserText, model: String, application: SourceApplication?, date: Date)`
  - `init(repitch: TranslationResult, source: UserText, model: String, application: SourceApplication?, date: Date)`
  - `init(correction: CorrectionResult, language: LanguageCode, profileID: String, model: String, application: SourceApplication?, date: Date)`
  - `init(explanation: ExplanationResult, source: UserText, language: LanguageCode, model: String, application: SourceApplication?, date: Date)`
  - Test helper `HistoryRecord.sample(...)` (in `HistoryFixtures.swift`).

- [ ] **Step 1: Write the fixtures and the failing tests**

`Tests/BabelOtterKitTests/History/HistoryFixtures.swift`:

```swift
import Foundation

@testable import BabelOtterKit

extension HistoryRecord {

    /// A synthetic record; every field can be overridden.
    static func sample(
        date: Date = Date(timeIntervalSince1970: 1_790_000_000),
        action: Action = .translate,
        sourceLanguage: LanguageCode = LanguageCode("de-CH"),
        targetLanguage: LanguageCode? = LanguageCode("en"),
        profileID: String? = "colleagues",
        model: String = "mistral-small3.2:24b",
        bundleID: String? = "com.apple.mail",
        appName: String? = "Mail",
        source: String = "Hallo zusammen",
        result: String = "Hello everyone"
    ) -> HistoryRecord {
        HistoryRecord(
            date: date, action: action, sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage, profileID: profileID, model: model,
            sourceBundleID: bundleID, sourceAppName: appName,
            source: UserText(source), result: UserText(result))
    }
}
```

`Tests/BabelOtterKitTests/History/HistoryRecordTests.swift`:

```swift
import Foundation
import Testing

@testable import BabelOtterKit

@Suite("A finished result becomes one history record")
struct HistoryRecordTests {

    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    private let mail = SourceApplication(
        processIdentifier: 42, bundleIdentifier: "com.apple.mail", name: "Mail")
    private let de = LanguageCode("de-CH")
    private let en = LanguageCode("en")

    private func translation(_ direction: Direction, _ text: String) -> TranslationResult {
        TranslationResult(
            text: UserText(text), direction: direction, warnings: ["w"],
            audience: .students, audienceInferred: true)
    }

    @Test("a translation keeps both languages, the audience and the translated text")
    func translationRecord() {
        let record = HistoryRecord(
            translation: translation(Direction(source: de, target: en), "Hello"),
            source: UserText("Hallo"), model: "m", application: mail, date: date)
        #expect(record == HistoryRecord(
            id: nil, date: date, action: .translate, sourceLanguage: de, targetLanguage: en,
            profileID: AudienceProfile.students.id, model: "m",
            sourceBundleID: "com.apple.mail", sourceAppName: "Mail",
            source: UserText("Hallo"), result: UserText("Hello")))
    }

    @Test("a re-pitch keeps its one language and no target")
    func repitchRecord() {
        let record = HistoryRecord(
            repitch: translation(Direction(source: de, target: de), "Guten Tag"),
            source: UserText("Hoi"), model: "m", application: mail, date: date)
        #expect(record.action == .repitch)
        #expect(record.sourceLanguage == de)
        #expect(record.targetLanguage == nil)
        #expect(record.profileID == AudienceProfile.students.id)
        #expect(record.source == UserText("Hoi"))
        #expect(record.result == UserText("Guten Tag"))
    }

    @Test("a correction keeps the original and the corrected text")
    func correctionRecord() {
        let result = CorrectionResult(
            original: UserText("Ich gehe morgen nach hause."),
            corrected: UserText("Ich gehe morgen nach Hause."),
            errors: [], suggestions: [], diff: [], warnings: [], hasNoErrors: false)
        let record = HistoryRecord(
            correction: result, language: de, profileID: "colleagues", model: "m",
            application: mail, date: date)
        #expect(record.action == .correct)
        #expect(record.sourceLanguage == de)
        #expect(record.targetLanguage == nil)
        #expect(record.profileID == "colleagues")
        #expect(record.source == UserText("Ich gehe morgen nach hause."))
        #expect(record.result == UserText("Ich gehe morgen nach Hause."))
    }

    @Test("an explanation reads German into English, has no audience, and keeps what Copy writes")
    func explanationRecord() {
        let result = ExplanationResult(
            summary: "The meeting moves.",
            notes: [ExplainNote(phrase: "verschoben", explanationEn: "postponed")],
            warnings: [])
        let record = HistoryRecord(
            explanation: result, source: UserText("Die Sitzung wird verschoben."),
            language: de, model: "m", application: mail, date: date)
        #expect(record.action == .explain)
        #expect(record.sourceLanguage == de)
        #expect(record.targetLanguage == en)
        #expect(record.profileID == nil)
        #expect(record.result == UserText(result.copyText))
        #expect(record.result.value.contains("postponed"))
    }

    @Test("an unknown application leaves both application fields empty")
    func noApplication() {
        let record = HistoryRecord(
            translation: translation(Direction(source: de, target: en), "Hello"),
            source: UserText("Hallo"), model: "m", application: nil, date: date)
        #expect(record.sourceBundleID == nil)
        #expect(record.sourceAppName == nil)
    }

    @Test("an application without a bundle id keeps its name")
    func nameOnly() {
        let record = HistoryRecord(
            translation: translation(Direction(source: de, target: en), "Hello"),
            source: UserText("Hallo"), model: "m",
            application: SourceApplication(processIdentifier: 1, bundleIdentifier: nil, name: "Tool"),
            date: date)
        #expect(record.sourceBundleID == nil)
        #expect(record.sourceAppName == "Tool")
    }

    @Test("describing a record never shows its text")
    func redacted() {
        let record = HistoryRecord.sample(source: "Geheimer Entwurf", result: "Secret draft")
        let shown = String(describing: record) + String(reflecting: record)
        #expect(!shown.contains("Geheimer"))
        #expect(!shown.contains("Secret"))
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --filter HistoryRecordTests 2>&1 | tail -20`
Expected: build FAILS with "cannot find 'HistoryRecord' in scope".

- [ ] **Step 3: Implement**

`Sources/BabelOtterKit/History/HistoryRecord.swift`:

```swift
import Foundation

/// One completed action, as history keeps it (#67, `FR-HIS-01`).
///
/// `source` and `result` are `UserText`, so describing or dumping a record
/// shows neither (`NFR-P5`).
public struct HistoryRecord: Sendable, Equatable {
    /// Nil until a store has kept the record.
    public var id: Int64?
    public let date: Date
    public let action: Action
    public let sourceLanguage: LanguageCode
    /// Translate's target, and English for Explain; nil for Correct and
    /// Re-pitch, which keep the text's language.
    public let targetLanguage: LanguageCode?
    /// The audience the result was written for; nil for Explain.
    public let profileID: String?
    public let model: String
    public let sourceBundleID: String?
    public let sourceAppName: String?
    public let source: UserText
    /// What Replace or Copy would have used.
    public let result: UserText

    public init(
        id: Int64? = nil, date: Date, action: Action, sourceLanguage: LanguageCode,
        targetLanguage: LanguageCode?, profileID: String?, model: String,
        sourceBundleID: String?, sourceAppName: String?, source: UserText, result: UserText
    ) {
        self.id = id
        self.date = date
        self.action = action
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.profileID = profileID
        self.model = model
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.source = source
        self.result = result
    }
}

extension HistoryRecord {

    public init(
        translation result: TranslationResult, source: UserText, model: String,
        application: SourceApplication?, date: Date
    ) {
        self.init(
            date: date, action: .translate, sourceLanguage: result.direction.source,
            targetLanguage: result.direction.target, profileID: result.audience.id,
            model: model, sourceBundleID: application?.bundleIdentifier,
            sourceAppName: application?.name, source: source, result: result.text)
    }

    /// Re-pitch runs with the source equal to the target: one language.
    public init(
        repitch result: TranslationResult, source: UserText, model: String,
        application: SourceApplication?, date: Date
    ) {
        self.init(
            date: date, action: .repitch, sourceLanguage: result.direction.source,
            targetLanguage: nil, profileID: result.audience.id,
            model: model, sourceBundleID: application?.bundleIdentifier,
            sourceAppName: application?.name, source: source, result: result.text)
    }

    public init(
        correction result: CorrectionResult, language: LanguageCode, profileID: String,
        model: String, application: SourceApplication?, date: Date
    ) {
        self.init(
            date: date, action: .correct, sourceLanguage: language,
            targetLanguage: nil, profileID: profileID,
            model: model, sourceBundleID: application?.bundleIdentifier,
            sourceAppName: application?.name, source: result.original, result: result.corrected)
    }

    /// The result is what Copy writes: the summary and the notes.
    public init(
        explanation result: ExplanationResult, source: UserText, language: LanguageCode,
        model: String, application: SourceApplication?, date: Date
    ) {
        self.init(
            date: date, action: .explain, sourceLanguage: language,
            targetLanguage: LanguageCode("en"), profileID: nil,
            model: model, sourceBundleID: application?.bundleIdentifier,
            sourceAppName: application?.name, source: source,
            result: UserText(result.copyText))
    }
}
```

In `.github/workflows/mutation.yml`, add after the line `Sources/BabelOtterKit/Config/LanguageConfig.swift` in PASS1:

```
          Sources/BabelOtterKit/History/HistoryRecord.swift
```

- [ ] **Step 4: Run the tests to see them pass, then the whole suite**

Run: `swift test --filter HistoryRecordTests 2>&1 | tail -20`
Expected: 7 tests pass.
Run: `swift test 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterKit/History/HistoryRecord.swift Tests/BabelOtterKitTests/History .github/workflows/mutation.yml
git commit -m "feat(history): a finished result becomes one record (#67)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `HistoryStore` and `InMemoryHistoryStore`

**Files:**
- Create: `Sources/BabelOtterKit/History/HistoryStore.swift`
- Modify: `.github/workflows/mutation.yml` (PASS1 list)
- Test: `Tests/BabelOtterKitTests/History/HistoryStoreContractTests.swift`

**Interfaces:**
- Consumes: `HistoryRecord`, `HistoryRecord.sample(...)`.
- Produces: `public protocol HistoryStore: Sendable { func add(_ record: HistoryRecord) throws -> Int64; func recent(limit: Int) throws -> [HistoryRecord] }`; `public enum HistoryStoreError: Error, Equatable { case cannotOpen(String), statementFailed(String), newerSchema(Int) }`; `public final class InMemoryHistoryStore: HistoryStore` with `public init()`; `enum StoreKind` in the test file (Task 4 adds `.sqlite`).

- [ ] **Step 1: Write the failing contract tests**

`Tests/BabelOtterKitTests/History/HistoryStoreContractTests.swift`:

```swift
import Foundation
import Testing

@testable import BabelOtterKit

/// Every store, the same promises.
enum StoreKind: String, CaseIterable, CustomTestStringConvertible {
    case memory

    var testDescription: String { rawValue }

    func make() throws -> any HistoryStore {
        switch self {
        case .memory:
            return InMemoryHistoryStore()
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
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --filter HistoryStoreContractTests 2>&1 | tail -20`
Expected: build FAILS with "cannot find type 'HistoryStore' in scope".

- [ ] **Step 3: Implement**

`Sources/BabelOtterKit/History/HistoryStore.swift`:

```swift
import Foundation

/// Where history is kept (#67). #68 adds search and #69 deletion when they
/// need them.
public protocol HistoryStore: Sendable {
    /// Keeps the record and returns its new id. The record's own `id` is
    /// ignored.
    func add(_ record: HistoryRecord) throws -> Int64
    /// Newest first (by date, then id), at most `limit`; none for a limit
    /// below 1.
    func recent(limit: Int) throws -> [HistoryRecord]
}

/// Never carries record text: only SQLite's or the file system's message.
public enum HistoryStoreError: Error, Equatable {
    case cannotOpen(String)
    case statementFailed(String)
    /// The file's `user_version`, higher than this build understands.
    case newerSchema(Int)
}

/// A `HistoryStore` in memory, for tests.
public final class InMemoryHistoryStore: HistoryStore, @unchecked Sendable {

    private var records: [HistoryRecord] = []
    private var nextID: Int64 = 1
    private let lock = NSLock()

    public init() {}

    public func add(_ record: HistoryRecord) throws -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let id = nextID
        nextID += 1
        var stored = record
        stored.id = id
        records.append(stored)
        return id
    }

    public func recent(limit: Int) throws -> [HistoryRecord] {
        lock.lock()
        defer { lock.unlock() }
        if limit < 1 { return [] }
        return Array(records.sorted(by: Self.isNewer).prefix(limit))
    }

    /// Later date first; for the same date, the higher id.
    static func isNewer(_ lhs: HistoryRecord, _ rhs: HistoryRecord) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return (lhs.id ?? 0) > (rhs.id ?? 0)
    }
}
```

In `.github/workflows/mutation.yml`, add after `Sources/BabelOtterKit/History/HistoryRecord.swift`:

```
          Sources/BabelOtterKit/History/HistoryStore.swift
```

- [ ] **Step 4: Run the tests to see them pass, then the whole suite**

Run: `swift test --filter HistoryStoreContractTests 2>&1 | tail -20`
Expected: 7 tests pass (one argument each).
Run: `swift test 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterKit/History/HistoryStore.swift Tests/BabelOtterKitTests/History/HistoryStoreContractTests.swift .github/workflows/mutation.yml
git commit -m "feat(history): the store protocol and an in-memory store (#67)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `SQLiteHistoryStore`

**Files:**
- Create: `Sources/BabelOtterKit/History/SQLiteHistoryStore.swift`
- Modify: `.github/workflows/mutation.yml` (PASS1 list)
- Modify: `Tests/BabelOtterKitTests/History/HistoryStoreContractTests.swift` (add `.sqlite` to `StoreKind`)
- Test: `Tests/BabelOtterKitTests/History/SQLiteHistoryStoreTests.swift`

**Interfaces:**
- Consumes: `HistoryStore`, `HistoryStoreError`, `HistoryRecord`, `StorageLocator`.
- Produces: `public final class SQLiteHistoryStore: HistoryStore` with `public static let fileName = "history.sqlite"`, `public static func open(at url: URL) throws -> SQLiteHistoryStore`, `public static func inApplicationSupport(locator: StorageLocator) throws -> SQLiteHistoryStore`; internal `func pragmaValue(_ name: String) throws -> String` for tests.

- [ ] **Step 1: Write the failing tests**

In `HistoryStoreContractTests.swift`, change `StoreKind` to:

```swift
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
```

`Tests/BabelOtterKitTests/History/SQLiteHistoryStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --filter "SQLiteHistoryStoreTests|HistoryStoreContractTests" 2>&1 | tail -20`
Expected: build FAILS with "cannot find 'SQLiteHistoryStore' in scope".

- [ ] **Step 3: Implement**

`Sources/BabelOtterKit/History/SQLiteHistoryStore.swift`:

```swift
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
```

In `.github/workflows/mutation.yml`, add after `Sources/BabelOtterKit/History/HistoryStore.swift`:

```
          Sources/BabelOtterKit/History/SQLiteHistoryStore.swift
```

- [ ] **Step 4: Run the tests to see them pass, then the whole suite**

Run: `swift test --filter "SQLiteHistoryStoreTests|HistoryStoreContractTests" 2>&1 | tail -20`
Expected: 11 SQLite tests and 14 contract cases (7 x 2) pass.
Run: `swift test 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterKit/History/SQLiteHistoryStore.swift Tests/BabelOtterKitTests/History .github/workflows/mutation.yml
git commit -m "feat(history): a private SQLite store on the system library (#67)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The menu says when history is not saved

**Files:**
- Create: `Sources/BabelOtterKit/History/HistoryProblem.swift`
- Modify: `Sources/BabelOtterKit/Readiness/ReadinessPolicy.swift` (facts, cause, policy)
- Modify: `.github/workflows/mutation.yml` (PASS1 list)
- Test: `Tests/BabelOtterKitTests/History/HistoryProblemTests.swift`, `Tests/BabelOtterKitTests/Readiness/ReadinessPolicyTests.swift`

**Interfaces:**
- Consumes: `HistoryStoreError`, `StorageLocationError`.
- Produces: `public enum HistoryProblem { static func opening(_ error: any Error) -> String; static func saving(_ error: any Error) -> String }`; `ReadinessFacts.historyProblem: String?` (init parameter `historyProblem: String? = nil`, after `configurationProblems`); `ReadinessCause.historyProblem(String)` with header and detail `"History: not saved - <reason>"`, `.degraded`, remedy nil.

- [ ] **Step 1: Write the failing tests**

`Tests/BabelOtterKitTests/History/HistoryProblemTests.swift`:

```swift
import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Why history is not saved, in a few words")
struct HistoryProblemTests {

    @Test("a database that cannot be opened names SQLite's reason")
    func cannotOpen() {
        #expect(HistoryProblem.opening(HistoryStoreError.cannotOpen("file is not a database"))
            == "could not open the database (file is not a database)")
        #expect(HistoryProblem.opening(HistoryStoreError.statementFailed("disk I/O error"))
            == "could not open the database (disk I/O error)")
    }

    @Test("a newer database names its version")
    func newer() {
        #expect(HistoryProblem.opening(HistoryStoreError.newerSchema(3))
            == "the database was written by a newer lingoSwen (version 3)")
    }

    @Test("a refused folder says why")
    func refusedFolder() {
        let url = URL(filePath: "/Users/x/Documents/h")
        #expect(HistoryProblem.opening(StorageLocationError.iCloudSynced(url))
            == "its folder syncs to iCloud")
        #expect(HistoryProblem.opening(StorageLocationError.notAbsolute(url))
            == "its folder is not an absolute path")
    }

    @Test("a failed write names SQLite's reason")
    func saving() {
        #expect(HistoryProblem.saving(HistoryStoreError.statementFailed("database is locked"))
            == "could not save (database is locked)")
    }

    @Test("any other error falls back to its description")
    func other() {
        let error = CocoaError(.fileWriteNoPermission)
        #expect(HistoryProblem.opening(error)
            == "could not open the database (\(error.localizedDescription))")
        #expect(HistoryProblem.saving(error)
            == "could not save (\(error.localizedDescription))")
    }
}
```

Append to `ReadinessPolicyTests.swift`, inside the suite (and add `historyProblem: String? = nil` as the last parameter of the `facts(...)` helper, passed through as `historyProblem: historyProblem`):

```swift
    // MARK: - History (#67)

    @Test("a history problem is degraded, says history is not saved, and offers no command")
    func historyProblemCause() {
        let cause = ReadinessCause.historyProblem("could not save (disk full)")
        #expect(cause.readiness == .degraded)
        #expect(cause.header == "History: not saved - could not save (disk full)")
        #expect(cause.detail == "History: not saved - could not save (disk full)")
        #expect(cause.remedy == nil)
    }

    @Test("a history problem comes after configuration problems and before the daemon")
    func historyProblemOrder() {
        let report = policy.report(for: facts(
            probe: .unreachable(detail: "refused"),
            configurationProblems: ["a"], historyProblem: "x"))
        #expect(report.causes == [
            .configurationProblem("a"),
            .historyProblem("x"),
            .ollamaUnreachable(detail: "refused"),
        ])
    }

    @Test("no history problem adds no cause")
    func noHistoryProblem() {
        #expect(policy.report(for: facts(historyProblem: nil)).causes.isEmpty)
    }
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift test --filter "HistoryProblemTests|ReadinessPolicyTests" 2>&1 | tail -20`
Expected: build FAILS with "cannot find 'HistoryProblem' in scope" and "type 'ReadinessCause' has no member 'historyProblem'".

- [ ] **Step 3: Implement**

`Sources/BabelOtterKit/History/HistoryProblem.swift`:

```swift
import Foundation

/// Why history is not being saved, worded to follow "History: not saved - "
/// in the menu (#67). Never carries record text.
public enum HistoryProblem {

    public static func opening(_ error: any Error) -> String {
        if let failure = error as? HistoryStoreError {
            return opening(failure)
        }
        if let refusal = error as? StorageLocationError {
            return refused(refusal)
        }
        return "could not open the database (\(error.localizedDescription))"
    }

    public static func saving(_ error: any Error) -> String {
        if case .statementFailed(let message)? = error as? HistoryStoreError {
            return "could not save (\(message))"
        }
        return "could not save (\(error.localizedDescription))"
    }

    private static func opening(_ failure: HistoryStoreError) -> String {
        switch failure {
        case .cannotOpen(let message), .statementFailed(let message):
            return "could not open the database (\(message))"
        case .newerSchema(let version):
            return "the database was written by a newer lingoSwen (version \(version))"
        }
    }

    private static func refused(_ refusal: StorageLocationError) -> String {
        switch refusal {
        case .iCloudSynced:
            return "its folder syncs to iCloud"
        case .notAbsolute:
            return "its folder is not an absolute path"
        }
    }
}
```

In `ReadinessPolicy.swift`:
- `ReadinessFacts`: add `public let historyProblem: String?` with the doc comment `/// Why history is not saved, worded to follow "History: not saved - "; nil when it is.`, an init parameter `historyProblem: String? = nil` after `configurationProblems`, and `self.historyProblem = historyProblem`.
- `ReadinessCause`: add `case historyProblem(String)` after `configurationProblem`. In `readiness`, add it to the `.degraded` list. In `detail` and `header`, add `case .historyProblem(let text): return "History: not saved - \(text)"`. In `remedy`, add `case .historyProblem: return nil`.
- `ReadinessPolicy.report(for:)`: after the configuration-problems loop add

```swift
        if let problem = facts.historyProblem {
            causes += [.historyProblem(problem)]
        }
```

and update the doc comment's order to "Accessibility, configuration problems, history, then the daemon, ...".

In `.github/workflows/mutation.yml`, add after `Sources/BabelOtterKit/History/HistoryStore.swift`:

```
          Sources/BabelOtterKit/History/HistoryProblem.swift
```

- [ ] **Step 4: Run the tests to see them pass, then the whole suite**

Run: `swift test --filter "HistoryProblemTests|ReadinessPolicyTests" 2>&1 | tail -20`
Expected: all pass, including 5 new problem tests and 3 new readiness tests.
Run: `swift test 2>&1 | tail -5`
Expected: all pass. (The app target must also still build: `swift build 2>&1 | tail -5`, expected no errors; any `switch` over `ReadinessCause` in the app that fails to compile gets the new case with the same handling as `.configurationProblem` minus the remedy.)

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterKit/History/HistoryProblem.swift Sources/BabelOtterKit/Readiness/ReadinessPolicy.swift Tests/BabelOtterKitTests .github/workflows/mutation.yml
git commit -m "feat(history): the menu says when history is not saved (#67)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The app records each popup's last finished result

**Files:**
- Create: `Sources/BabelOtterApp/AppStorage.swift`, `Sources/BabelOtterApp/HistoryRecorder.swift`
- Modify: `Sources/BabelOtterApp/ConfigurationSource.swift:20-26`, `Sources/BabelOtterApp/ReadinessMonitor.swift`, `Sources/BabelOtterApp/PopupModel.swift`, `Sources/BabelOtterApp/AppDelegate.swift`

**Interfaces:**
- Consumes: `SQLiteHistoryStore.inApplicationSupport(locator:)`, `HistoryStore`, `HistoryRecord` constructors, `HistoryProblem`, `ReadinessFacts(historyProblem:)`, `Configuration.model(for:)`, `Configuration.germanLanguage`.
- Produces: `PopupModel.init(..., record: @escaping @MainActor (HistoryRecord) -> Void, ...)`; `PopupModel.recordHistory()`.

The app target has no tests; this task is verified by `swift build`, the whole suite, and manual checks H1-H5 (Task 7).

- [ ] **Step 1: One storage locator for the app**

`Sources/BabelOtterApp/AppStorage.swift`:

```swift
import BabelOtterKit
import Foundation

/// Where the app may keep files, decided once (NFR-P7). `config.json` and
/// `history.sqlite` live in the same folder, so they are always checked
/// against the same synced roots.
enum AppStorage {

    static func locator() -> StorageLocator {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // The directories iCloud Drive can sync on this machine.
        return StorageLocator(
            home: home,
            iCloudRoots: ["Library/Mobile Documents", "Documents", "Desktop"]
                .map { home.appending(path: $0) })
    }
}
```

In `ConfigurationSource.init`, replace the `home` and `locator` lines with `let locator = AppStorage.locator()`.

- [ ] **Step 2: The recorder**

`Sources/BabelOtterApp/HistoryRecorder.swift`:

```swift
import BabelOtterKit
import Foundation

/// Opens history once at launch and writes each popup's record (#67).
///
/// A store that cannot be opened leaves history off for the session; a write
/// that fails loses that record. Either way `problem` says why, for the menu,
/// and every action keeps working. No record text reaches a log.
@MainActor
final class HistoryRecorder {

    private let store: (any HistoryStore)?
    /// Worded to follow "History: not saved - "; nil while history works.
    private(set) var problem: String?
    var onChange: (@MainActor () -> Void)?

    init() {
        do {
            store = try SQLiteHistoryStore.inApplicationSupport(locator: AppStorage.locator())
            problem = nil
        } catch {
            store = nil
            problem = HistoryProblem.opening(error)
        }
    }

    func record(_ record: HistoryRecord) {
        guard let store else { return }
        let before = problem
        do {
            _ = try store.add(record)
            problem = nil
        } catch {
            problem = HistoryProblem.saving(error)
        }
        if problem != before { onChange?() }
    }
}
```

- [ ] **Step 3: Readiness carries the problem**

In `ReadinessMonitor.swift`, below `var configurationProblems: [String] = []` add:

```swift
    /// Set by `AppDelegate` whenever history starts or stops saving (#67).
    var historyProblem: String?
```

and pass `historyProblem: historyProblem` to `ReadinessFacts(...)` in `check()`, after `configurationProblems: configurationProblems`.

- [ ] **Step 4: The popup keeps a pending record and writes it once**

In `PopupModel.swift`:

1. Stored properties, below `private let reopen: ...`:

```swift
    /// Writes a record to history; the app's `HistoryRecorder` (#67).
    private let record: @MainActor (HistoryRecord) -> Void
    /// The last result that finished in this popup. A new run does not clear
    /// it, so closing during a Regenerate still keeps the earlier result.
    private var pendingRecord: HistoryRecord?
    /// Set once the pending record is written, so no way out writes twice.
    private var recorded = false
```

2. `init` gains `record: @escaping @MainActor (HistoryRecord) -> Void` after `environment:` and sets `self.record = record`.

3. A helper below `recordHistory` (step 4.5):

```swift
    /// Keeps a finished result for history, with what the snapshot knows.
    private func keep(_ make: (UserText, SourceApplication) -> HistoryRecord) {
        guard let snapshot else { return }
        pendingRecord = make(snapshot.text, snapshot.application)
    }
```

4. In each `.finished` case, after `phase = .finished`:

   - `apply(_ event: TranslationEvent)`:

```swift
            let model = configuration.model(for: action)
            if action == .repitch {
                keep { HistoryRecord(repitch: result, source: $0, model: model, application: $1, date: Date()) }
            } else {
                keep { HistoryRecord(translation: result, source: $0, model: model, application: $1, date: Date()) }
            }
```

   - `applyExplanation`:

```swift
            let model = configuration.model(for: action)
            let language = configuration.germanLanguage.code
            keep {
                HistoryRecord(
                    explanation: result, source: $0, language: language, model: model,
                    application: $1, date: Date())
            }
```

   - `applyCorrection`:

```swift
            let model = configuration.model(for: action)
            let language = configuration.germanLanguage.code
            let profileID = audience.audience.id
            keep { _, application in
                HistoryRecord(
                    correction: result, language: language, profileID: profileID,
                    model: model, application: application, date: Date())
            }
```

5. `recordHistory()`, above `dismiss()`:

```swift
    /// Writes the pending record, once, on every way out: Dismiss/Escape,
    /// Copy after its pause, a Replace that lets the popup go, a new hotkey,
    /// and quitting. Nothing finished, nothing written.
    func recordHistory() {
        guard !recorded else { return }
        guard let pendingRecord else { return }
        recorded = true
        self.pendingRecord = nil
        record(pendingRecord)
    }
```

6. `dismiss()` becomes:

```swift
    func dismiss() {
        recordHistory()
        isDismissed = true
        stop()
        close()
    }
```

7. In `settle(_:)`, `guard custody.keepsPopupOpen else { return }` becomes:

```swift
        guard custody.keepsPopupOpen else {
            recordHistory()
            return
        }
```

- [ ] **Step 5: The app delegate opens history and passes it in**

In `AppDelegate.swift`:

1. Below `private let source = ConfigurationSource()`:

```swift
    /// Opened once; survives configuration reloads (#67).
    private let history = HistoryRecorder()
```

2. In `applicationDidFinishLaunching`, after `pushConfigurationProblems()`:

```swift
        history.onChange = { [weak self] in self?.pushHistoryProblem() }
        pushHistoryProblem()
```

3. A new method below `pushConfigurationProblems()`:

```swift
    private func pushHistoryProblem() {
        monitor.historyProblem = history.problem
        monitor.refresh()
    }
```

4. Both `PopupModel(...)` calls (in `startAction` and `showAccessibilityNeeded`) gain, after `environment: environment,`:

```swift
            record: { [weak self] record in self?.history.record(record) },
```

5. A termination handler, below `applicationDidFinishLaunching`:

```swift
    /// A popup still open when the app quits keeps its result (#67).
    func applicationWillTerminate(_ notification: Notification) {
        currentModel?.recordHistory()
    }
```

- [ ] **Step 6: Build and run the whole suite**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` with no errors.
Run: `swift test 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/BabelOtterApp
git commit -m "feat(history): each popup's last finished result is recorded when it closes (#67)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Hand-over and README

**Files:**
- Modify: `docs/HANDOFF.md` (new update section at the top, below the intro line)
- Modify: `README.md:29-31`

- [ ] **Step 1: Count the tests**

Run: `swift test 2>&1 | /usr/bin/grep -E "Test run with .* tests" | tail -1`
Expected: a line like `Test run with N tests in M suites passed`. Note N and M.

- [ ] **Step 2: HANDOFF**

Insert below `Read this first if you are picking babelOtter up in a new session.` (and change the title date to 2026-10-19):

```markdown
## Update 2026-10-19: history is recorded (#67)

Each popup's last finished result is written to `~/Library/Application Support/ch.lingoswen/history.sqlite` when the popup closes: source, result, action, languages, audience, model, time and source app. Regenerate replaces the pending record rather than adding one; a popup closed before anything finished records nothing. The file is `0600`, excluded from backup, `secure_delete` on, rollback journal (no `-wal`). If the database cannot be opened or a write fails, the menu shows "History: not saved - <reason>" and everything else works. Kit: `BabelOtterKit/History/` (`HistoryRecord`, `HistoryStore`, `SQLiteHistoryStore` on the system `libsqlite3`, `HistoryProblem`); app: `HistoryRecorder`, `PopupModel.recordHistory()`. There is no window yet (#68), no retention or Clear All (#69). Spec: `docs/superpowers/specs/2026-10-19-history-record-design.md`.

To look: `sqlite3 ~/Library/Application\ Support/ch.lingoswen/history.sqlite 'select id, action, source_language, target_language, profile_id, model, source_app_name, substr(result_text,1,40) from records order by id desc limit 5'`

**Manual check (yours):**

| # | Do | Expect |
|---|---|---|
| H1 | Translate a text, press Regenerate, wait for it, press Escape | Exactly one new row, holding the second result |
| H2 | Press Escape while the first run is still streaming; then try Translate on a French text (refused) | No new row either time |
| H3 | Replace a translation; Copy one; Explain one and close it; then make Replace fail (quit the source app first) and Dismiss; then leave a finished popup open and quit from the menu | One new row each time, five in all |
| H4 | `ls -l ~/Library/Application\ Support/ch.lingoswen/` | `history.sqlite` is `-rw-------`; there is no `history.sqlite-wal` |
| H5 | Quit; `chmod 000` the folder's `history.sqlite`; start the app and translate something; then `chmod 600` it back | The menu shows "History: not saved - could not open the database (...)"; Translate still works |
```

- [ ] **Step 3: README**

Replace the sentence `` `swift test` runs 777 tests in 73 suites, all green. A settings window, onboarding and history are not built yet `` (it spans the line break between lines 29 and 30) with `` `swift test` runs N tests in M suites, all green. Every finished result is kept in a private local history (#67); a settings window, onboarding and the history window are not built yet `` using the numbers from Step 1. Read lines 28-31 first and edit across the line break.

- [ ] **Step 4: Commit**

```bash
git add docs/HANDOFF.md README.md
git commit -m "docs(history): hand-over and README for #67

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
