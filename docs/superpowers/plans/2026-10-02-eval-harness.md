# Evaluation Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `swift run babelotter-eval` runs a fixed, synthetic golden set through the real `Corrector` and `Translator` on every installed model, scores each case the same way every time, and prints a per-model comparison table, the misses, and a saved JSON result that a later run can be compared against.

**Architecture:** Everything that decides anything is pure and lives in `Sources/BabelOtterKit/Eval/`:

- whole-word text search;
- golden-set types, a loader and its validation;
- the two scorers, with chrF;
- per-model summaries, with deltas;
- argument parsing and case selection;
- the saved-run record and the report text.

All of it is test-first and mutation-gated. `Sources/babelotter-eval/main.swift` is a thin runner: read the files, call the pipelines, time them, print, save. The golden set lives in `evals/golden/`; its cases are drafted, then reviewed by the user before they are committed.

**Tech Stack:** Swift 6 (tools 6.0), SwiftPM, Swift Testing, Foundation only. Zero dependencies.

**Spec:** `docs/superpowers/specs/2026-09-30-eval-harness-design.md` (covers #74, #75, #76; parent spec section 4.14, `FR-EVL-01`..`04`, `NFR-P8`).

## Global Constraints

- **Zero dependencies** (`DependencyAllowlistTests`).
- **One networking call site.** `NetworkingCallSiteTests` scans every file under `Sources/`, the CLI included. No new file may contain `URLSession`, `URLRequest`, `socket(`, `connect(`, `send(`, `recv(` or `(contentsOf:`, in code or in comments. Read files with `FileManager.default.contents(atPath:)`; build the client with `OllamaClient.loopback(timeout:)`; use `+=`, never `append(contentsOf:)`. (`URLError` and `write(to:` are fine.)
- **Kit sources are ASCII-only** (`AsciiSourceTests`). Write `"\u{00DF}"` for the eszett and `"\u{27E6}"`/`"\u{27E7}"` for the sentinel brackets. Test files and the golden JSON may contain any character.
- **The kit imports no UI framework** (`NoUIImportsTests`).
- **Every new kit file goes into `PASS1`** in `.github/workflows/mutation.yml`. Add each line just before the final `Sources/BabelOtterKit/Text/WordDiff.swift"` line, keeping that line's closing quote last. The file-list check fails loudly otherwise.
- **muter traps** (see `docs/HANDOFF.md`):
  - no `while a < b, predicate` comma-conjunction;
  - no ternary whose condition ends in an enum member (use `switch`);
  - no `guard ... else { ...; return }` inside a `do` block inside a `Task` closure.
  - Before writing a test to kill a reported survivor, plant that mutant by hand at muter's line and column. muter 16 drops mutants inside closures and nested loops and reports them as survivors.
- **Public types the CLI constructs need an explicit `public init`.** A memberwise init is internal, even on a public struct. Types only the kit constructs keep the internal memberwise init, which tests reach through `@testable import`.
- **CI compiles with Swift 6.1.2 / Xcode 16.4** (`macos-15`); local is Swift 6.4. Use nothing newer than Swift 6.1.
- **The golden set is synthetic and public** (`NFR-P8`). No real names, institutions, addresses, emails or numbers. Real texts are inspiration only, rewritten. **The user reviews both golden files before they are committed** (Task 9).
- **The CLI never runs in CI.** Only the kit tests and the golden-file validation run there.
- **Paths: `evals/`, lowercase.** The spec says `Evals/`, but `FixtureContentGuardTests.scannedDirectories` and `.gitignore` already use `evals`. Lowercase means the guard already scans the golden set with no change, and Task 1 corrects the spec.
- **Commit messages** end with a blank line and `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- **Local test runs:** `swift test` (Xcode is selected). If it ever fails with "plugin for module 'TestingMacros' not found", the Command Line Tools are selected instead; run `sudo xcode-select -s /Applications/Xcode.app`.

## Review Focus

1. **A `wrong` that is a prefix of its own correction** ("jetz" -> "jetzt", which is the spec's own example). With plain substring matching the corrected text still "contains" `jetz`, so the fix can never count as found. Expected: matching is on whole words, so "jetzt" does not contain the word "jetz". Pinned in Task 1 (search) and Task 3 (recall).
2. **A golden case that can never pass, or can never fail.** A `mustNot` already present in the text, or a `right` alternative that itself contains `wrong`, would pass or fail regardless of the model. Expected: `GoldenSet.load` rejects the case, naming its id and field. Pinned in Task 2.
3. **`--only` with a mistyped case id.** Expected: an error naming the unknown id, never a run of zero cases that looks green. Pinned in Task 7.
4. **A model that stalls, or Ollama dying mid-run.** Expected: that case is recorded as a `timeout` or `other` failure (recall 0, all checks failed), and the run carries on with the next case. Pinned by `EvalFailure`'s error mapping in Task 3. The carry-on behaviour is the CLI's `do`/`catch` per case in Task 10, checked in the live run.
5. **`--compare` against a run with different models.** Expected: deltas only for models present in both runs, and only for metrics both runs have; no crash and no invented baseline. Pinned in Task 6 (`delta`) and Task 8 (table).

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/BabelOtterKit/Eval/TextSearch.swift` (create) | Whole-word and plain occurrences by character offset; word counting |
| `Sources/BabelOtterKit/Eval/GoldenSet.swift` (create) | `CorrectionCase`, `ExpectedFix`, `TranslationCase`, `TranslationDirection`, `GoldenSet.load`, `GoldenSetError` |
| `Sources/BabelOtterKit/Eval/EvalOutcome.swift` (create) | `EvalFailure` and its mapping from pipeline errors |
| `Sources/BabelOtterKit/Eval/CorrectionScorer.swift` (create) | `CorrectionOutcome`, `CorrectionScore`, `CorrectionScorer` |
| `Sources/BabelOtterKit/Eval/ChrF.swift` (create) | chrF, n = 1...6, beta = 2 |
| `Sources/BabelOtterKit/Eval/TranslationScorer.swift` (create) | `TranslationOutcome`, `TranslationScore`, `TranslationScorer` |
| `Sources/BabelOtterKit/Eval/EvalSummary.swift` (create) | `Metric`, `MetricDelta`, `EvalSummary`, `Latency`, `CorrectionSummary`, `TranslationSummary` |
| `Sources/BabelOtterKit/Eval/EvalArguments.swift` (create) | `EvalArguments.parse`, `EvalSelection`, case selection |
| `Sources/BabelOtterKit/Eval/EvalRun.swift` (create) | `CaseRecord`, `EvalRun` (the saved JSON) |
| `Sources/BabelOtterKit/Eval/EvalReport.swift` (create) | The comparison table and the miss lines, as text |
| `Sources/babelotter-eval/main.swift` (replace) | The runner |
| `evals/golden/correction.json`, `evals/golden/translation.json` (create) | The golden set |
| `Tests/BabelOtterKitTests/Eval/*Tests.swift` (create) | One suite per kit file, plus `GoldenFilesTests` |
| `.github/workflows/mutation.yml` (modify) | `PASS1` gains each new kit file |
| `.gitignore` (modify) | `evals/results/` |
| `docs/superpowers/specs/2026-09-30-eval-harness-design.md` (modify) | Path, whole-word matching, the optional fields |
| `docs/HANDOFF.md` (modify) | State after the harness |

---

### Task 1: Whole-word search, and the spec brought in line

**Files:**
- Create: `Sources/BabelOtterKit/Eval/TextSearch.swift`
- Test: `Tests/BabelOtterKitTests/Eval/TextSearchTests.swift`
- Modify: `.github/workflows/mutation.yml`
- Modify: `docs/superpowers/specs/2026-09-30-eval-harness-design.md`

**Interfaces:**
- Produces (internal, used by Tasks 2-4):
  - `TextSearch.occurrences(of needle: String, in text: String, wholeWords: Bool) -> [Range<Int>]`: character offsets, overlapping occurrences included;
  - `TextSearch.contains(_ needle: String, in text: String) -> Bool`: whole words;
  - `TextSearch.wordCount(_ text: String) -> Int`: runs of letters or digits;
  - `TextSearch.isWordCharacter(_ character: Character) -> Bool`.

A side of `needle` needs a word boundary only when the needle's own character on that side is a letter or digit. So `", und"` matches right after "gut", and `"jetz"` does not match inside "jetzt".

- [ ] **Step 1: Write the failing tests**

```swift
import Testing

@testable import BabelOtterKit

@Suite("Eval: whole-word search")
struct TextSearchTests {

    @Test("a word is not found inside a longer word")
    func notInsideLongerWord() {
        #expect(TextSearch.occurrences(of: "jetz", in: "Ich bin jetzt da.", wholeWords: true).isEmpty)
        #expect(!TextSearch.contains("jetz", in: "Ich bin jetzt da."))
        #expect(!TextSearch.contains("Sätze", in: "Zwei Sätzen."))
        #expect(!TextSearch.contains("3", in: "Um 13 Uhr."))
        #expect(!TextSearch.contains("bin", in: "Ich binde."))
    }

    @Test("plain search finds a word inside a longer one")
    func plainFindsInside() {
        #expect(TextSearch.occurrences(of: "jetz", in: "jetzt", wholeWords: false) == [0..<4])
        #expect(TextSearch.occurrences(of: "\u{00DF}", in: "Stra\u{00DF}e", wholeWords: false) == [4..<5])
    }

    @Test("a whole word is found at the edges and next to punctuation")
    func edgesAndPunctuation() {
        #expect(TextSearch.occurrences(of: "jetz", in: "jetz", wholeWords: true) == [0..<4])
        #expect(TextSearch.occurrences(of: "jetz", in: "Bin jetz.", wholeWords: true) == [4..<8])
        #expect(TextSearch.occurrences(of: "eine Sätze", in: "(eine Sätze)", wholeWords: true) == [1..<11])
    }

    @Test("a needle that starts or ends with punctuation needs no boundary on that side")
    func punctuationEdge() {
        #expect(TextSearch.occurrences(of: ", und", in: "gut, und", wholeWords: true) == [3..<8])
        #expect(TextSearch.occurrences(of: "gut,", in: "gut,und", wholeWords: true) == [0..<4])
    }

    @Test("every occurrence is reported, in order")
    func everyOccurrence() {
        #expect(TextSearch.occurrences(of: "der", in: "der Hund, der Ball", wholeWords: true)
            == [0..<3, 10..<13])
    }

    @Test("an empty needle, or one longer than the text, is never found")
    func degenerate() {
        #expect(TextSearch.occurrences(of: "", in: "abc", wholeWords: false).isEmpty)
        #expect(TextSearch.occurrences(of: "abcd", in: "abc", wholeWords: false).isEmpty)
    }

    @Test("words are runs of letters or digits", arguments: [
        ("Ich habe 3 Sätze, ok.", 5),
        ("", 0),
        (" - ", 0),
        ("E-Mail", 2),
        ("Strasse", 1),
    ])
    func wordCount(text: String, expected: Int) {
        #expect(TextSearch.wordCount(text) == expected)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter TextSearchTests`
Expected: FAIL to compile, "cannot find 'TextSearch' in scope".

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Where a phrase occurs in a text, by character offset.
///
/// Scoring compares phrases the golden set names ("jetz", "eine Saetze")
/// with what a model wrote. Plain substring search is wrong for that: the
/// correct "jetzt" contains the wrong "jetz", so a fix would never count as
/// found. Whole-word search is what every scorer uses unless it says
/// otherwise.
enum TextSearch {

    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// Every occurrence of `needle` in `text`, overlapping ones included.
    ///
    /// With `wholeWords`, an occurrence must not touch a letter or digit on
    /// a side where the needle itself begins or ends with one. A needle that
    /// starts with punctuation (", und") needs no boundary before it.
    static func occurrences(of needle: String, in text: String, wholeWords: Bool) -> [Range<Int>] {
        let haystack = Array(text)
        let pattern = Array(needle)
        guard let first = pattern.first, let last = pattern.last, pattern.count <= haystack.count
        else { return [] }
        var found: [Range<Int>] = []
        for start in 0...(haystack.count - pattern.count) {
            let end = start + pattern.count
            guard haystack[start..<end].elementsEqual(pattern) else { continue }
            if wholeWords && touchesWord(haystack, start, end, first, last) { continue }
            found.append(start..<end)
        }
        return found
    }

    /// Whether `needle` occurs in `text` as whole words.
    static func contains(_ needle: String, in text: String) -> Bool {
        !occurrences(of: needle, in: text, wholeWords: true).isEmpty
    }

    static func wordCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for character in text {
            let isWord = isWordCharacter(character)
            if isWord && !inWord { count += 1 }
            inWord = isWord
        }
        return count
    }

    private static func touchesWord(
        _ haystack: [Character], _ start: Int, _ end: Int, _ first: Character, _ last: Character
    ) -> Bool {
        let before = start > 0 && isWordCharacter(first) && isWordCharacter(haystack[start - 1])
        let after = end < haystack.count && isWordCharacter(last) && isWordCharacter(haystack[end])
        return before || after
    }
}
```

- [ ] **Step 4: Run them to verify they pass**

Run: `swift test --filter TextSearchTests`
Expected: PASS.

- [ ] **Step 5: Plant two defects and watch them fail**

Planted defects, not a mutation run. Each must fail at least one test; revert each before the next.
- In `touchesWord`, replace `before || after` with `before && after`. Expected: `notInsideLongerWord` fails.
- In `occurrences`, delete `isWordCharacter(first) &&`. Expected: `punctuationEdge` fails.

- [ ] **Step 6: Add the file to the mutation list**

In `.github/workflows/mutation.yml`, insert this line just before `          Sources/BabelOtterKit/Text/WordDiff.swift"`:

```
          Sources/BabelOtterKit/Eval/TextSearch.swift
```

- [ ] **Step 7: Bring the spec in line with what is being built**

In `docs/superpowers/specs/2026-09-30-eval-harness-design.md`:

1. Replace every `Evals/` with `evals/`. In section 3, replace "whose roots are extended to `Evals/golden/`" with "which already scans `evals/`".
2. In 3.1, after the `right` bullet, add: "- Matching is on whole words: `wrong` must not touch a letter or digit on a side where it begins or ends with one. Otherwise the correct `jetzt` would still contain the wrong `jetz`."
3. In 3.1, after the `profile` bullet, add: "- `terms` is optional (default none): do-not-translate terms for the case, which must occur in `text`."
4. In 3.2, after the `terms` bullet, add: "- `profile` is optional (default `colleagues`), so translation cases can mix registers."
5. In 4.1's validation list, add these rules:
   - "every `mustNot` is absent from the text";
   - "no `right` alternative contains `wrong` as whole words";
   - "a case that is not clean has at least one fix or one `mustNot`";
   - "the profile is a shipped profile id";
   - "every translation term also occurs in `reference`, and `reference` is non-empty".

- [ ] **Step 8: Commit**

```bash
git add Sources/BabelOtterKit/Eval/TextSearch.swift Tests/BabelOtterKitTests/Eval/TextSearchTests.swift \
  .github/workflows/mutation.yml docs/superpowers/specs/2026-09-30-eval-harness-design.md
git commit -m "feat(eval): whole-word search for scoring

The spec's own example (jetz -> jetzt) can never count as found with
plain substring matching. The spec now says whole words, lowercase
evals/, and the extra validation rules.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Golden-set types, loader and validation

**Files:**
- Create: `Sources/BabelOtterKit/Eval/GoldenSet.swift`
- Test: `Tests/BabelOtterKitTests/Eval/GoldenSetTests.swift`
- Modify: `.github/workflows/mutation.yml`

**Interfaces:**
- Consumes: `TextSearch.occurrences`, `TextSearch.contains` (Task 1); `ErrorCategory`, `AudienceProfile.shippedDefaults`, `AudienceProfile.colleagues`, `LanguageConfig.english`, `LanguageConfig.swissGerman`, `Direction` (existing).
- Produces:
  - `public struct ExpectedFix: Sendable, Equatable { wrong: String; right: [String]; category: ErrorCategory }`
  - `public struct CorrectionCase: Sendable, Equatable { id: String; text: String; profileID: String; terms: [String]; fixes: [ExpectedFix]; mustNot: [String]; clean: Bool }`
  - `public enum TranslationDirection: String { case englishToSwissGerman = "en-de-ch", swissGermanToEnglish = "de-ch-en" }`, with `direction: Direction` and `targetIsGerman: Bool`
  - `public struct TranslationCase: Sendable, Equatable { id; text; direction: TranslationDirection; profileID; terms; reference }`
  - `public struct GoldenSet: Sendable, Equatable { correction: [CorrectionCase]; translation: [TranslationCase] }`, with `public static func load(correction: Data, translation: Data) throws -> GoldenSet` (throws `GoldenSetError`)
  - `public struct GoldenSetError: Error, Equatable, CustomStringConvertible { file: String; caseID: String?; field: String; reason: String }`

  Memberwise inits stay internal; tests build cases through them.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import BabelOtterKit

private func load(_ correction: String, _ translation: String = "[]") throws -> GoldenSet {
    try GoldenSet.load(correction: Data(correction.utf8), translation: Data(translation.utf8))
}

/// The error a single bad correction case raises.
private func correctionError(_ caseJSON: String) -> GoldenSetError? {
    do {
        _ = try load("[\(caseJSON)]")
        return nil
    } catch let error as GoldenSetError {
        return error
    } catch {
        return nil
    }
}

private func translationError(_ caseJSON: String) -> GoldenSetError? {
    do {
        _ = try load("[]", "[\(caseJSON)]")
        return nil
    } catch let error as GoldenSetError {
        return error
    } catch {
        return nil
    }
}

@Suite("Eval: the golden set loads and validates")
struct GoldenSetTests {

    @Test("a minimal correction case loads with its defaults")
    func correctionDefaults() throws {
        let set = try load("""
            [{"id": "a", "text": "Ich bin jetz da.",
              "fixes": [{"wrong": "jetz", "right": ["jetzt"], "category": "spelling"}]}]
            """)
        #expect(set.correction == [CorrectionCase(
            id: "a", text: "Ich bin jetz da.", profileID: "colleagues", terms: [],
            fixes: [ExpectedFix(wrong: "jetz", right: ["jetzt"], category: .spelling)],
            mustNot: [], clean: false)])
    }

    @Test("a translation case loads with its defaults and direction")
    func translationDefaults() throws {
        let set = try load("[]", """
            [{"id": "t", "text": "Hello Otterbach.", "direction": "en-de-ch",
              "terms": ["Otterbach"], "reference": "Hallo Otterbach."}]
            """)
        let only = try #require(set.translation.first)
        #expect(only.profileID == "colleagues")
        #expect(only.direction == .englishToSwissGerman)
        #expect(only.direction.direction == Direction(source: LanguageCode("en"), target: LanguageCode("de-CH")))
        #expect(only.direction.targetIsGerman)
        #expect(!TranslationDirection.swissGermanToEnglish.targetIsGerman)
    }

    @Test("a clean case and a guard-only case are valid")
    func cleanAndGuardOnly() throws {
        let set = try load("""
            [{"id": "c", "text": "Alles gut.", "fixes": [], "clean": true},
             {"id": "g", "text": "mit der Kollege", "fixes": [], "mustNot": ["Kollegin"]}]
            """)
        #expect(set.correction.map(\.clean) == [true, false])
    }

    @Test("an invalid correction case names its id and field", arguments: [
        (#"{"id": "", "text": "x", "fixes": [], "clean": true}"#, "id"),
        (#"{"id": "a", "text": "", "fixes": [], "clean": true}"#, "text"),
        (#"{"id": "a", "text": "Hallo.", "profile": "nobody", "fixes": [], "clean": true}"#, "profile"),
        (#"{"id": "a", "text": "Hallo.", "terms": ["Otterbach"], "fixes": [], "clean": true}"#, "terms[0]"),
        (#"{"id": "a", "text": "Ich bin jetzt da.", "fixes": [{"wrong": "jetz", "right": ["jetzt"], "category": "spelling"}]}"#, "fixes[0].wrong"),
        (#"{"id": "a", "text": "Ich bin jetz da.", "fixes": [{"wrong": "jetz", "right": [], "category": "spelling"}]}"#, "fixes[0].right"),
        (#"{"id": "a", "text": "Ich bin jetz da.", "fixes": [{"wrong": "jetz", "right": [""], "category": "spelling"}]}"#, "fixes[0].right[0]"),
        (#"{"id": "a", "text": "Ich bin jetz da.", "fixes": [{"wrong": "bin jetz", "right": ["bin jetz schon"], "category": "spelling"}]}"#, "fixes[0].right[0]"),
        (#"{"id": "a", "text": "Ich bin jetz da.", "fixes": [{"wrong": "jetz", "right": ["jetzt"], "category": "typo"}]}"#, "fixes[0].category"),
        (#"{"id": "a", "text": "Ich bin jetz da.", "fixes": [{"wrong": "jetz", "right": ["jetzt"], "category": "spelling"}], "clean": true}"#, "fixes"),
        (#"{"id": "a", "text": "Ich bin da.", "fixes": []}"#, "fixes"),
        (#"{"id": "a", "text": "mit der Kollegin", "fixes": [], "mustNot": ["Kollegin"]}"#, "mustNot[0]"),
        (#"{"id": "a", "text": "Hallo.", "fixes": [], "mustNot": [""]}"#, "mustNot[0]"),
    ])
    func invalidCorrection(caseJSON: String, field: String) {
        let error = correctionError(caseJSON)
        #expect(error?.field == field)
        #expect(error?.file == "correction.json")
    }

    @Test("an invalid translation case names its id and field", arguments: [
        (#"{"id": "t", "text": "Hi.", "direction": "en-fr", "reference": "Salut."}"#, "direction"),
        (#"{"id": "t", "text": "Hi.", "direction": "en-de-ch", "reference": ""}"#, "reference"),
        (#"{"id": "t", "text": "Hi.", "direction": "en-de-ch", "terms": ["Otterbach"], "reference": "Hallo."}"#, "terms[0]"),
        (#"{"id": "t", "text": "Hi Otterbach.", "direction": "en-de-ch", "terms": ["Otterbach"], "reference": "Hallo."}"#, "terms[0]"),
        (#"{"id": "t", "text": "Hi.", "direction": "en-de-ch", "profile": "nobody", "reference": "Hallo."}"#, "profile"),
    ])
    func invalidTranslation(caseJSON: String, field: String) {
        let error = translationError(caseJSON)
        #expect(error?.field == field)
        #expect(error?.caseID == "t")
        #expect(error?.file == "translation.json")
    }

    @Test("ids are unique across both files")
    func duplicateAcrossFiles() {
        #expect(throws: GoldenSetError.self) {
            try load(
                #"[{"id": "same", "text": "Alles gut.", "fixes": [], "clean": true}]"#,
                #"[{"id": "same", "text": "Hi.", "direction": "en-de-ch", "reference": "Hallo."}]"#)
        }
    }

    @Test("malformed JSON is reported against its file")
    func malformed() {
        let error = correctionError("{")
        #expect(error?.field == "json")
        #expect(error?.caseID == nil)
    }

    @Test("the error reads as one line naming the file, case and field")
    func description() {
        let error = GoldenSetError(
            file: "correction.json", caseID: "a", field: "fixes[0].wrong", reason: "is missing")
        #expect(error.description == #"correction.json: case "a", fixes[0].wrong: is missing"#)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter GoldenSetTests`
Expected: FAIL to compile, "cannot find 'GoldenSet' in scope".

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// One error a correction case expects the model to fix.
public struct ExpectedFix: Sendable, Equatable {
    /// As the case's text has it; matched on whole words.
    public let wrong: String
    /// Acceptable corrections; any one of them counts.
    public let right: [String]
    public let category: ErrorCategory
}

public struct CorrectionCase: Sendable, Equatable {
    public let id: String
    public let text: String
    public let profileID: String
    /// Do-not-translate terms, added to the configuration for this case.
    public let terms: [String]
    public let fixes: [ExpectedFix]
    /// Strings that must not appear in the output: meaning guards.
    public let mustNot: [String]
    /// An error-free text, for measuring over-correction.
    public let clean: Bool
}

public enum TranslationDirection: String, Sendable, Equatable, CaseIterable {
    case englishToSwissGerman = "en-de-ch"
    case swissGermanToEnglish = "de-ch-en"

    public var direction: Direction {
        switch self {
        case .englishToSwissGerman:
            return Direction(source: LanguageConfig.english.code, target: LanguageConfig.swissGerman.code)
        case .swissGermanToEnglish:
            return Direction(source: LanguageConfig.swissGerman.code, target: LanguageConfig.english.code)
        }
    }

    /// Whether the target is the German locale, whose output must carry no eszett.
    public var targetIsGerman: Bool {
        switch self {
        case .englishToSwissGerman: return true
        case .swissGermanToEnglish: return false
        }
    }
}

public struct TranslationCase: Sendable, Equatable {
    public let id: String
    public let text: String
    public let direction: TranslationDirection
    public let profileID: String
    public let terms: [String]
    public let reference: String
}

public struct GoldenSetError: Error, Equatable, CustomStringConvertible {
    public let file: String
    public let caseID: String?
    public let field: String
    public let reason: String

    public var description: String {
        let place = caseID.map { "case \"\($0)\", " } ?? ""
        return "\(file): \(place)\(field): \(reason)"
    }
}

/// The evaluation harness's fixed cases (spec 2026-09-30, section 3).
///
/// Loading validates every case, because a case that can never pass -- or
/// never fail -- measures nothing and would quietly skew every score. The
/// first problem found is thrown, naming the file, the case and the field.
public struct GoldenSet: Sendable, Equatable {
    public let correction: [CorrectionCase]
    public let translation: [TranslationCase]

    static let correctionFile = "correction.json"
    static let translationFile = "translation.json"
    static let knownProfiles = Set(AudienceProfile.shippedDefaults.map(\.id))

    public static func load(correction: Data, translation: Data) throws -> GoldenSet {
        let rawCorrection = try decode([RawCorrectionCase].self, correction, file: correctionFile)
        let rawTranslation = try decode([RawTranslationCase].self, translation, file: translationFile)
        var ids: Set<String> = []
        var corrections: [CorrectionCase] = []
        for raw in rawCorrection {
            corrections.append(try validated(raw, ids: &ids))
        }
        var translations: [TranslationCase] = []
        for raw in rawTranslation {
            translations.append(try validated(raw, ids: &ids))
        }
        return GoldenSet(correction: corrections, translation: translations)
    }

    // MARK: - Decoding

    private struct RawFix: Decodable {
        let wrong: String
        let right: [String]
        let category: String
    }

    private struct RawCorrectionCase: Decodable {
        let id: String
        let text: String
        let profile: String?
        let terms: [String]?
        let fixes: [RawFix]
        let mustNot: [String]?
        let clean: Bool?
    }

    private struct RawTranslationCase: Decodable {
        let id: String
        let text: String
        let direction: String
        let profile: String?
        let terms: [String]?
        let reference: String
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data, file: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw GoldenSetError(file: file, caseID: nil, field: "json", reason: String(describing: error))
        }
    }

    // MARK: - Validation

    private typealias Failure = (_ field: String, _ reason: String) -> GoldenSetError

    private static func validated(_ raw: RawCorrectionCase, ids: inout Set<String>) throws -> CorrectionCase {
        let fail: Failure = { GoldenSetError(file: correctionFile, caseID: raw.id, field: $0, reason: $1) }
        try checkID(raw.id, ids: &ids, fail: fail)
        guard !raw.text.isEmpty else { throw fail("text", "is empty") }
        let profile = try checkedProfile(raw.profile, fail: fail)
        let terms = raw.terms ?? []
        try checkTerms(terms, occurIn: raw.text, fail: fail)
        var fixes: [ExpectedFix] = []
        for (index, fix) in raw.fixes.enumerated() {
            fixes.append(try validated(fix, field: "fixes[\(index)]", text: raw.text, fail: fail))
        }
        let mustNot = raw.mustNot ?? []
        for (index, phrase) in mustNot.enumerated() {
            guard !phrase.isEmpty else { throw fail("mustNot[\(index)]", "is empty") }
            guard !raw.text.contains(phrase) else {
                throw fail("mustNot[\(index)]", "\"\(phrase)\" is already in the text, so the guard can never pass")
            }
        }
        let clean = raw.clean ?? false
        if clean && !fixes.isEmpty { throw fail("fixes", "a clean case lists no fixes") }
        if !clean && fixes.isEmpty && mustNot.isEmpty {
            throw fail("fixes", "a case that is not clean needs at least one fix or mustNot guard")
        }
        return CorrectionCase(
            id: raw.id, text: raw.text, profileID: profile, terms: terms, fixes: fixes,
            mustNot: mustNot, clean: clean)
    }

    private static func validated(
        _ raw: RawFix, field: String, text: String, fail: Failure
    ) throws -> ExpectedFix {
        guard TextSearch.contains(raw.wrong, in: text) else {
            throw fail(field + ".wrong", "\"\(raw.wrong)\" does not occur in the text as whole words")
        }
        guard !raw.right.isEmpty else { throw fail(field + ".right", "lists no alternative") }
        for (index, alternative) in raw.right.enumerated() {
            guard !alternative.isEmpty else { throw fail("\(field).right[\(index)]", "is empty") }
            guard !TextSearch.contains(raw.wrong, in: alternative) else {
                throw fail("\(field).right[\(index)]", "contains \"\(raw.wrong)\", so the fix could never be found")
            }
        }
        guard let category = ErrorCategory(rawValue: raw.category) else {
            let known = ErrorCategory.allCases.map(\.rawValue).joined(separator: ", ")
            throw fail(field + ".category", "\"\(raw.category)\" is not one of: \(known)")
        }
        return ExpectedFix(wrong: raw.wrong, right: raw.right, category: category)
    }

    private static func validated(_ raw: RawTranslationCase, ids: inout Set<String>) throws -> TranslationCase {
        let fail: Failure = { GoldenSetError(file: translationFile, caseID: raw.id, field: $0, reason: $1) }
        try checkID(raw.id, ids: &ids, fail: fail)
        guard !raw.text.isEmpty else { throw fail("text", "is empty") }
        guard let direction = TranslationDirection(rawValue: raw.direction) else {
            let known = TranslationDirection.allCases.map(\.rawValue).joined(separator: ", ")
            throw fail("direction", "\"\(raw.direction)\" is not one of: \(known)")
        }
        let profile = try checkedProfile(raw.profile, fail: fail)
        guard !raw.reference.isEmpty else { throw fail("reference", "is empty") }
        let terms = raw.terms ?? []
        try checkTerms(terms, occurIn: raw.text, fail: fail)
        try checkTerms(terms, occurIn: raw.reference, fail: fail)
        return TranslationCase(
            id: raw.id, text: raw.text, direction: direction, profileID: profile, terms: terms,
            reference: raw.reference)
    }

    private static func checkID(_ id: String, ids: inout Set<String>, fail: Failure) throws {
        guard !id.isEmpty else { throw fail("id", "is empty") }
        guard ids.insert(id).inserted else { throw fail("id", "is used by another case") }
    }

    private static func checkedProfile(_ profile: String?, fail: Failure) throws -> String {
        let id = profile ?? AudienceProfile.colleagues.id
        guard knownProfiles.contains(id) else {
            let known = knownProfiles.sorted().joined(separator: ", ")
            throw fail("profile", "\"\(id)\" is not a shipped profile: \(known)")
        }
        return id
    }

    private static func checkTerms(_ terms: [String], occurIn text: String, fail: Failure) throws {
        for (index, term) in terms.enumerated() {
            guard !term.isEmpty, text.contains(term) else {
                throw fail("terms[\(index)]", "\"\(term)\" does not occur in the text it protects")
            }
        }
    }
}
```

- [ ] **Step 4: Run them to verify they pass**

Run: `swift test --filter GoldenSetTests`
Expected: PASS.

- [ ] **Step 5: Plant two defects and watch them fail**

Revert each before the next.
- Delete the `guard !TextSearch.contains(raw.wrong, in: alternative)` check. Expected: the `bin jetz schon` row of `invalidCorrection` fails.
- Change `if !clean && fixes.isEmpty && mustNot.isEmpty` to `if !clean && fixes.isEmpty`. Expected: `cleanAndGuardOnly` fails.

- [ ] **Step 6: Add the file to the mutation list**

In `.github/workflows/mutation.yml`, before the `WordDiff.swift"` line:

```
          Sources/BabelOtterKit/Eval/GoldenSet.swift
```

- [ ] **Step 7: Run the whole suite**

Run: `swift test`
Expected: PASS. `AsciiSourceTests` passes because `GoldenSet.swift` is ASCII.

- [ ] **Step 8: Commit**

```bash
git add Sources/BabelOtterKit/Eval/GoldenSet.swift Tests/BabelOtterKitTests/Eval/GoldenSetTests.swift .github/workflows/mutation.yml
git commit -m "feat(eval): golden-set types, loader and validation

A case that can never pass or never fail is rejected, naming its file,
id and field.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Failure kinds and the correction scorer

**Files:**
- Create: `Sources/BabelOtterKit/Eval/EvalOutcome.swift`
- Create: `Sources/BabelOtterKit/Eval/CorrectionScorer.swift`
- Test: `Tests/BabelOtterKitTests/Eval/CorrectionScorerTests.swift`
- Modify: `.github/workflows/mutation.yml`

**Interfaces:**
- Consumes: `CorrectionCase`, `ExpectedFix` (Task 2); `TextSearch` (Task 1); `CorrectionResult`, `CorrectionError`, `CorrectionFailure`, `TranslationError`, `DiffSegment`, `WordDiff` (existing).
- Produces:
  - `public enum EvalFailure: String, Codable, CaseIterable { unreadableReply, structureLost, notGerman, emptyResponse, timeout, other }`, with `public init(_ error: any Error)`
  - `public enum CorrectionOutcome: Sendable, Equatable { case corrected(CorrectionResult), failed(EvalFailure) }`
  - `public struct CorrectionScore: Sendable, Equatable, Codable`, with fields:
    - `caseID: String`, `failure: EvalFailure?`;
    - `expectedFixes: Int`, `missedFixes: [String]` (the `wrong` of each missed fix);
    - `overCorrectedWords: Int`, `originalWords: Int`;
    - `guardViolations: [String]`;
    - `categoryMatches: Int`, `unexplainedFixes: Int`;
    - `cleanPassed: Bool?` (nil unless the case is clean);
    - `warnings: Int`;
    - computed `foundFixes: Int` and `recall: Double?` (nil when nothing was expected).
  - `public enum CorrectionScorer { public static func score(_ testCase: CorrectionCase, outcome: CorrectionOutcome) -> CorrectionScore }`
  - internal, for tests: `CorrectionScorer.overCorrectedWords(in segments: [DiffSegment], original: String, fixes: [ExpectedFix]) -> Int` and `CorrectionScorer.categoryCheck(found: [ExpectedFix], original: String, errors: [CorrectionError]) -> (matches: Int, unexplained: Int)`

Scoring rules, from spec section 4.2 with Task 1's whole-word rule:

- **Found:** a fix counts when the corrected text no longer contains `wrong` and does contain at least one `right` alternative, both as whole words.
- **Over-correction:** walk the diff, tracking the position in the original:
  - a `same` or `removed` segment advances the position;
  - a `removed` segment covers `position..<position+count`;
  - an `added` segment sits at `position`.
  - A fix span is each whole-word occurrence of a fix's `wrong` in the original, widened by one character on each side.
  - A removed range that overlaps no span, or an added point that no span contains, contributes its word count.
- **Categories:** for each found fix, look at the listed errors whose `original` (plain occurrences, so a lone `ß` counts) overlaps an occurrence of the fix's `wrong`. No such error means the fix is unexplained. Otherwise it is a match when one of those errors has the expected category.
- **Guards:** plain `contains`.
- **Clean:** passes iff `hasNoErrors` and the corrected text equals the original.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import BabelOtterKit

private func fix(_ wrong: String, _ right: [String], _ category: ErrorCategory = .spelling) -> ExpectedFix {
    ExpectedFix(wrong: wrong, right: right, category: category)
}

private func testCase(
    _ text: String, fixes: [ExpectedFix] = [], mustNot: [String] = [], clean: Bool = false
) -> CorrectionCase {
    CorrectionCase(
        id: "case", text: text, profileID: "colleagues", terms: [], fixes: fixes,
        mustNot: mustNot, clean: clean)
}

private func item(_ original: String, _ category: ErrorCategory) -> CorrectionError {
    CorrectionError(
        original: original, corrected: "x", category: category, explanationEn: "because",
        severity: .error)
}

private func corrected(
    _ original: String, _ text: String, errors: [CorrectionError] = [],
    warnings: [String] = [], hasNoErrors: Bool = false
) -> CorrectionOutcome {
    .corrected(CorrectionResult(
        original: UserText(original), corrected: UserText(text), errors: errors, suggestions: [],
        diff: WordDiff.diff(original, text), warnings: warnings, hasNoErrors: hasNoErrors))
}

@Suite("Eval: a correction scored against its case")
struct CorrectionScorerTests {

    // MARK: Failures

    @Test("pipeline errors map to failure kinds")
    func failureMapping() {
        #expect(EvalFailure(CorrectionFailure.unreadableReply) == .unreadableReply)
        #expect(EvalFailure(CorrectionFailure.structureLost) == .structureLost)
        #expect(EvalFailure(CorrectionFailure.notGerman) == .notGerman)
        #expect(EvalFailure(CorrectionFailure.emptyResponse) == .emptyResponse)
        #expect(EvalFailure(TranslationError.emptyResponse) == .emptyResponse)
        #expect(EvalFailure(URLError(.timedOut)) == .timeout)
        #expect(EvalFailure(URLError(.cannotConnectToHost)) == .other)
        #expect(EvalFailure(TranslationError.languageNotConfigured(LanguageCode("fr"))) == .other)
    }

    @Test("a failed correction misses every fix and fails a clean case")
    func failedOutcome() {
        let failing = testCase("Ich bin jetz da.", fixes: [fix("jetz", ["jetzt"])])
        let score = CorrectionScorer.score(failing, outcome: .failed(.timeout))
        #expect(score.failure == .timeout)
        #expect(score.missedFixes == ["jetz"])
        #expect(score.recall == 0)
        #expect(score.cleanPassed == nil)
        #expect(score.originalWords == 4)

        let clean = CorrectionScorer.score(testCase("Alles gut.", clean: true), outcome: .failed(.other))
        #expect(clean.cleanPassed == false)
        #expect(clean.recall == nil)
    }

    // MARK: Recall

    @Test("a fix counts when wrong is gone and an alternative is present")
    func recallWithAlternatives() {
        let text = "Heute bin ich jetz sehr müde."
        let theCase = testCase(text, fixes: [
            fix("jetz", ["jetzt"]),
            fix("bin ich jetz", ["bin jetzt", "ich bin jetzt"], .wordOrder),
        ])
        let score = CorrectionScorer.score(theCase, outcome: corrected(text, "Heute bin jetzt sehr müde."))
        #expect(score.missedFixes.isEmpty)
        #expect(score.foundFixes == 2)
        #expect(score.recall == 1)
    }

    @Test("wrong gone without any right alternative is a miss")
    func wrongGoneRightAbsent() {
        let text = "Ich bin jetz da."
        let score = CorrectionScorer.score(
            testCase(text, fixes: [fix("jetz", ["jetzt"])]), outcome: corrected(text, "Ich bin nun da."))
        #expect(score.missedFixes == ["jetz"])
    }

    @Test("a right alternative present while wrong remains is a miss")
    func rightPresentWrongRemains() {
        let text = "Ich bin jetz da, jetz."
        let score = CorrectionScorer.score(
            testCase(text, fixes: [fix("jetz", ["jetzt"])]),
            outcome: corrected(text, "Ich bin jetzt da, jetz."))
        #expect(score.missedFixes == ["jetz"])
    }

    @Test("a wrong that is a prefix of its correction is still found")
    func prefixOfCorrection() {
        let text = "Ich bin jetz da."
        let score = CorrectionScorer.score(
            testCase(text, fixes: [fix("jetz", ["jetzt"])]), outcome: corrected(text, "Ich bin jetzt da."))
        #expect(score.recall == 1)
    }

    // MARK: Guards, clean cases, warnings

    @Test("a mustNot string in the output is a violation")
    func guards() {
        let text = "Ich habe mit der Kollege gesprochen."
        let theCase = testCase(text, fixes: [fix("der Kollege", ["dem Kollegen"], .grammaticalCase)],
                               mustNot: ["Kollegin"])
        let bad = CorrectionScorer.score(theCase, outcome: corrected(text, "Ich habe mit der Kollegin gesprochen."))
        #expect(bad.guardViolations == ["Kollegin"])
        let good = CorrectionScorer.score(theCase, outcome: corrected(text, "Ich habe mit dem Kollegen gesprochen."))
        #expect(good.guardViolations.isEmpty)
    }

    @Test("a clean case passes only unchanged and with no errors")
    func cleanCases() {
        let text = "Alles ist gut."
        let theCase = testCase(text, clean: true)
        #expect(CorrectionScorer.score(theCase, outcome: corrected(text, text, hasNoErrors: true)).cleanPassed == true)
        #expect(CorrectionScorer.score(theCase, outcome: corrected(text, text, hasNoErrors: false)).cleanPassed == false)
        #expect(CorrectionScorer.score(theCase, outcome: corrected(text, "Alles ist sehr gut.", hasNoErrors: true)).cleanPassed == false)
        let notClean = testCase("Ich bin jetz da.", fixes: [fix("jetz", ["jetzt"])])
        #expect(CorrectionScorer.score(notClean, outcome: corrected("Ich bin jetz da.", "Ich bin jetzt da.")).cleanPassed == nil)
    }

    @Test("warnings are counted")
    func warnings() {
        let text = "Ich bin jetz da."
        let score = CorrectionScorer.score(
            testCase(text, fixes: [fix("jetz", ["jetzt"])]),
            outcome: corrected(text, "Ich bin jetzt da.", warnings: ["one", "two"]))
        #expect(score.warnings == 2)
    }

    // MARK: Over-correction

    @Test("a change inside a fix span is not over-correction")
    func insideSpan() {
        let text = "Ich habe jetz Zeit."
        let score = CorrectionScorer.score(
            testCase(text, fixes: [fix("jetz", ["jetzt"])]), outcome: corrected(text, "Ich habe jetzt Zeit."))
        #expect(score.overCorrectedWords == 0)
        #expect(score.originalWords == 4)
    }

    @Test("a change outside every fix span counts its removed and added words")
    func outsideSpan() {
        let text = "Ich habe jetz Zeit."
        let score = CorrectionScorer.score(
            testCase(text, fixes: [fix("jetz", ["jetzt"])]), outcome: corrected(text, "Ich habe jetzt Ruhe."))
        // "Zeit" -> "Ruhe" is two words away from the fix: one removed, one added.
        // (A change right next to the fix, such as "habe" -> "hatte", sits in
        // its one-character widening and counts as inside, by design.)
        #expect(score.overCorrectedWords == 2)
    }

    @Test("an insertion at a fix's edge is inside; one character further is outside")
    func insertionAtEdge() {
        let fixes = [fix("jetz", ["jetzt"])]
        // "ab jetz cd": "jetz" is 3..<7, widened to 2..<8.
        let atEnd: [DiffSegment] = [.same("ab jetz"), .added(" nun"), .same(" cd")]
        #expect(CorrectionScorer.overCorrectedWords(in: atEnd, original: "ab jetz cd", fixes: fixes) == 0)
        let atStart: [DiffSegment] = [.same("ab "), .added("nun "), .same("jetz cd")]
        #expect(CorrectionScorer.overCorrectedWords(in: atStart, original: "ab jetz cd", fixes: fixes) == 0)
        let pastEdge: [DiffSegment] = [.same("ab jetz "), .added("nun "), .same("cd")]
        #expect(CorrectionScorer.overCorrectedWords(in: pastEdge, original: "ab jetz cd", fixes: fixes) == 1)
    }

    @Test("an addition after a removal sits where the removal ended")
    func additionAfterRemoval() {
        let fixes = [fix("jetz", ["jetzt"])]
        let replaced: [DiffSegment] = [.same("ab "), .removed("jetz"), .added("jetzt"), .same(" cd")]
        #expect(CorrectionScorer.overCorrectedWords(in: replaced, original: "ab jetz cd", fixes: fixes) == 0)
        let later: [DiffSegment] = [.same("ab jetz "), .removed("cd"), .added("ef gh")]
        #expect(CorrectionScorer.overCorrectedWords(in: later, original: "ab jetz cd", fixes: fixes) == 3)
    }

    @Test("with no fixes, every changed word is over-correction")
    func noFixes() {
        let segments: [DiffSegment] = [.same("Alles "), .removed("ist"), .added("war"), .same(" gut.")]
        #expect(CorrectionScorer.overCorrectedWords(in: segments, original: "Alles ist gut.", fixes: []) == 2)
    }

    // MARK: Categories

    @Test("a found fix with an overlapping item of the right category matches")
    func categoryMatch() {
        let found = [fix("der Kollege", ["dem Kollegen"], .grammaticalCase)]
        let result = CorrectionScorer.categoryCheck(
            found: found, original: "mit der Kollege", errors: [item("der Kollege", .grammaticalCase)])
        #expect(result.matches == 1)
        #expect(result.unexplained == 0)
    }

    @Test("an overlapping item of another category is explained but not a match")
    func categoryMismatch() {
        let found = [fix("der Kollege", ["dem Kollegen"], .grammaticalCase)]
        let result = CorrectionScorer.categoryCheck(
            found: found, original: "mit der Kollege", errors: [item("Kollege", .gender)])
        #expect(result.matches == 0)
        #expect(result.unexplained == 0)
    }

    @Test("a found fix no item overlaps is unexplained")
    func unexplained() {
        let found = [fix("jetz", ["jetzt"])]
        let result = CorrectionScorer.categoryCheck(
            found: found, original: "Ich bin jetz da.", errors: [item("Ich", .spelling)])
        #expect(result.matches == 0)
        #expect(result.unexplained == 1)
    }

    @Test("an item inside a word overlaps it, as the eszett row does")
    func itemInsideWord() {
        let found = [fix("Stra\u{00DF}e", ["Strasse"])]
        let result = CorrectionScorer.categoryCheck(
            found: found, original: "Die Stra\u{00DF}e ist lang.", errors: [item("\u{00DF}", .spelling)])
        #expect(result.matches == 1)
    }

    @Test("the scorer reports category matches for found fixes only")
    func categoriesOnlyForFound() {
        let text = "Ich bin jetz da und mude."
        let theCase = testCase(text, fixes: [fix("jetz", ["jetzt"]), fix("mude", ["müde"])])
        let score = CorrectionScorer.score(
            theCase,
            outcome: corrected(text, "Ich bin jetzt da und mude.", errors: [item("jetz", .spelling), item("mude", .spelling)]))
        #expect(score.categoryMatches == 1)
        #expect(score.unexplainedFixes == 0)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter CorrectionScorerTests`
Expected: FAIL to compile, "cannot find 'EvalFailure' in scope".

- [ ] **Step 3: Write `EvalOutcome.swift`**

```swift
import Foundation

/// Why a case produced no result. Recall is then 0, and the kind is
/// reported on its own so a parse problem is never mistaken for a weak model.
public enum EvalFailure: String, Sendable, Equatable, Codable, CaseIterable {
    case unreadableReply
    case structureLost
    case notGerman
    case emptyResponse
    case timeout
    case other

    public init(_ error: any Error) {
        if let failure = error as? CorrectionFailure {
            self = Self.kind(of: failure)
        } else if let failure = error as? TranslationError, failure == .emptyResponse {
            self = .emptyResponse
        } else if let failure = error as? URLError, failure.code == .timedOut {
            self = .timeout
        } else {
            self = .other
        }
    }

    private static func kind(of failure: CorrectionFailure) -> EvalFailure {
        switch failure {
        case .unreadableReply: return .unreadableReply
        case .structureLost: return .structureLost
        case .notGerman: return .notGerman
        case .emptyResponse: return .emptyResponse
        }
    }
}
```

- [ ] **Step 4: Write `CorrectionScorer.swift`**

```swift
import Foundation

public enum CorrectionOutcome: Sendable, Equatable {
    case corrected(CorrectionResult)
    case failed(EvalFailure)
}

public struct CorrectionScore: Sendable, Equatable, Codable {
    public let caseID: String
    public let failure: EvalFailure?
    public let expectedFixes: Int
    /// The `wrong` of every fix not found.
    public let missedFixes: [String]
    public let overCorrectedWords: Int
    public let originalWords: Int
    public let guardViolations: [String]
    public let categoryMatches: Int
    public let unexplainedFixes: Int
    /// Nil unless the case is clean.
    public let cleanPassed: Bool?
    public let warnings: Int

    public var foundFixes: Int { expectedFixes - missedFixes.count }

    /// Nil for a case that expects no fixes (a clean or guard-only case).
    public var recall: Double? {
        guard expectedFixes > 0 else { return nil }
        return Double(foundFixes) / Double(expectedFixes)
    }
}

/// One correction scored against its case (spec 2026-09-30, section 4.2).
public enum CorrectionScorer {

    public static func score(_ testCase: CorrectionCase, outcome: CorrectionOutcome) -> CorrectionScore {
        switch outcome {
        case .failed(let failure):
            return CorrectionScore(
                caseID: testCase.id, failure: failure, expectedFixes: testCase.fixes.count,
                missedFixes: testCase.fixes.map(\.wrong), overCorrectedWords: 0,
                originalWords: TextSearch.wordCount(testCase.text), guardViolations: [],
                categoryMatches: 0, unexplainedFixes: 0,
                cleanPassed: cleanVerdict(testCase, passed: false), warnings: 0)
        case .corrected(let result):
            return score(testCase, result)
        }
    }

    private static func score(_ testCase: CorrectionCase, _ result: CorrectionResult) -> CorrectionScore {
        let corrected = result.corrected.value
        let found = testCase.fixes.filter { isFound($0, in: corrected) }
        let missed = testCase.fixes.filter { !isFound($0, in: corrected) }
        let categories = categoryCheck(found: found, original: testCase.text, errors: result.errors)
        let unchanged = result.hasNoErrors && corrected == testCase.text
        return CorrectionScore(
            caseID: testCase.id, failure: nil, expectedFixes: testCase.fixes.count,
            missedFixes: missed.map(\.wrong),
            overCorrectedWords: overCorrectedWords(in: result.diff, original: testCase.text, fixes: testCase.fixes),
            originalWords: TextSearch.wordCount(testCase.text),
            guardViolations: testCase.mustNot.filter { corrected.contains($0) },
            categoryMatches: categories.matches, unexplainedFixes: categories.unexplained,
            cleanPassed: cleanVerdict(testCase, passed: unchanged), warnings: result.warnings.count)
    }

    private static func cleanVerdict(_ testCase: CorrectionCase, passed: Bool) -> Bool? {
        guard testCase.clean else { return nil }
        return passed
    }

    /// `wrong` is gone and some alternative is present, both as whole words.
    static func isFound(_ fix: ExpectedFix, in corrected: String) -> Bool {
        !TextSearch.contains(fix.wrong, in: corrected)
            && fix.right.contains { TextSearch.contains($0, in: corrected) }
    }

    /// Words changed outside every expected fix's span.
    static func overCorrectedWords(in segments: [DiffSegment], original: String, fixes: [ExpectedFix]) -> Int {
        let spans = fixes
            .flatMap { TextSearch.occurrences(of: $0.wrong, in: original, wholeWords: true) }
            .map { ($0.lowerBound - 1)..<($0.upperBound + 1) }
        var position = 0
        var count = 0
        for segment in segments {
            switch segment {
            case .same(let text):
                position += text.count
            case .removed(let text):
                let covered = position..<(position + text.count)
                if !spans.contains(where: { $0.overlaps(covered) }) { count += TextSearch.wordCount(text) }
                position += text.count
            case .added(let text):
                if !spans.contains(where: { $0.contains(position) }) { count += TextSearch.wordCount(text) }
            }
        }
        return count
    }

    /// For each found fix: is it explained by an overlapping item, and does
    /// one such item carry the expected category?
    static func categoryCheck(
        found: [ExpectedFix], original: String, errors: [CorrectionError]
    ) -> (matches: Int, unexplained: Int) {
        var matches = 0
        var unexplained = 0
        for fix in found {
            let fixRanges = TextSearch.occurrences(of: fix.wrong, in: original, wholeWords: true)
            let overlapping = errors.filter { error in
                TextSearch.occurrences(of: error.original, in: original, wholeWords: false)
                    .contains { range in fixRanges.contains { $0.overlaps(range) } }
            }
            if overlapping.isEmpty {
                unexplained += 1
            } else if overlapping.contains(where: { $0.category == fix.category }) {
                matches += 1
            }
        }
        return (matches, unexplained)
    }
}
```

- [ ] **Step 5: Run them to verify they pass**

Run: `swift test --filter CorrectionScorerTests`
Expected: PASS.

- [ ] **Step 6: Plant three defects and watch them fail**

Revert each before the next.
- In `isFound`, replace `&&` with `||`. Expected: `wrongGoneRightAbsent` and `rightPresentWrongRemains` fail.
- In `overCorrectedWords`, change `+ 1` (upper bound) to `+ 0`. Expected: `insertionAtEdge` fails.
- In `overCorrectedWords`, move `position += text.count` out of the `.removed` case. Expected: `additionAfterRemoval` fails.

- [ ] **Step 7: Add both files to the mutation list**

Before the `WordDiff.swift"` line:

```
          Sources/BabelOtterKit/Eval/CorrectionScorer.swift
          Sources/BabelOtterKit/Eval/EvalOutcome.swift
```

- [ ] **Step 8: Run the whole suite**

Run: `swift test`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Sources/BabelOtterKit/Eval/EvalOutcome.swift Sources/BabelOtterKit/Eval/CorrectionScorer.swift \
  Tests/BabelOtterKitTests/Eval/CorrectionScorerTests.swift .github/workflows/mutation.yml
git commit -m "feat(eval): score a correction against its case

Recall with alternatives, over-correction outside fix spans, meaning
guards, category matching by overlap, clean cases, warnings, and
failure kinds.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: chrF

**Files:**
- Create: `Sources/BabelOtterKit/Eval/ChrF.swift`
- Test: `Tests/BabelOtterKitTests/Eval/ChrFTests.swift`
- Modify: `.github/workflows/mutation.yml`

**Interfaces:**
- Produces: `public enum ChrF { public static func score(hypothesis: String, reference: String) -> Double }`, from 0 to 100.

Definition (Popovic 2015, the original chrF; not sacrebleu's per-order average):
- Whitespace is removed from both strings.
- For n = 1...6, count character n-grams in each string as multisets. `matched` is the sum over grams of `min(hypCount, refCount)`. `P_n = matched / hypTotal` and `R_n = matched / refTotal`.
- An order with no n-grams on either side is skipped.
- `P` and `R` are the arithmetic means over the orders that were not skipped. The score is `100 * (1 + beta^2) * P * R / (beta^2 * P + R)` with `beta = 2`.
- The score is 0 when every order is skipped or the denominator is 0.

- [ ] **Step 1: Write the failing tests**

Expected values, worked by hand:

- `"ab"` against `"abc"`:
  - n = 1: P = 2/2, R = 2/3; n = 2: P = 1/1, R = 1/2; n = 3..6 have no hypothesis grams and are skipped.
  - P = 1, R = 7/12.
  - F = 5 * (7/12) / (4 + 7/12) = 35/55 = **63.6364**.
  - Averaging F per order instead gives 63.49, which this pins against.
- `"aa"` against `"a"`:
  - n = 1: matched = min(2, 1) = 1, P = 1/2, R = 1/1; n = 2 has no reference grams and is skipped.
  - F = 5 * 0.5 / (2 + 1) = **83.3333**.

```swift
import Testing

@testable import BabelOtterKit

private func close(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 0.001 }

@Suite("Eval: chrF")
struct ChrFTests {

    @Test("identical text scores 100")
    func identical() {
        #expect(close(ChrF.score(hypothesis: "Guten Morgen", reference: "Guten Morgen"), 100))
    }

    @Test("nothing in common scores 0")
    func disjoint() {
        #expect(ChrF.score(hypothesis: "ab", reference: "cd") == 0)
    }

    @Test("precision and recall are averaged over orders before the F-score")
    func handComputed() {
        #expect(close(ChrF.score(hypothesis: "ab", reference: "abc"), 63.6364))
    }

    @Test("matches are clipped to the reference count")
    func clipped() {
        #expect(close(ChrF.score(hypothesis: "aa", reference: "a"), 83.3333))
    }

    @Test("recall weighs more than precision")
    func betaTwo() {
        let short = ChrF.score(hypothesis: "ab", reference: "abc")
        let long = ChrF.score(hypothesis: "abc", reference: "ab")
        #expect(short < long)
    }

    @Test("whitespace is ignored")
    func whitespace() {
        #expect(close(ChrF.score(hypothesis: "a b\nc", reference: "abc"), 100))
    }

    @Test("an empty side scores 0")
    func empty() {
        #expect(ChrF.score(hypothesis: "", reference: "abc") == 0)
        #expect(ChrF.score(hypothesis: "abc", reference: "") == 0)
        #expect(ChrF.score(hypothesis: "  ", reference: " ") == 0)
    }

    @Test("orders above six are not used")
    func sixOrders() {
        // One wrong last character in seven. For each n = 1...6 both sides
        // have 8-n grams and 7-n of them match, so P_n = R_n = (7-n)/(8-n).
        // A seventh order would add a term to the mean and change the score.
        let score = ChrF.score(hypothesis: "abcdefX", reference: "abcdefg")
        let ratios = (1...6).map { Double(7 - $0) / Double(8 - $0) }
        let mean = ratios.reduce(0, +) / 6
        #expect(close(score, 100 * mean))
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter ChrFTests`
Expected: FAIL to compile, "cannot find 'ChrF' in scope".

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Character n-gram F-score (Popovic 2015): n = 1...6, beta = 2.
///
/// Precision and recall are averaged over the orders first, then combined,
/// as in the original definition. Whitespace is ignored, so a translation is
/// not rewarded or punished for spacing.
public enum ChrF {

    static let maxOrder = 6
    static let beta = 2.0

    public static func score(hypothesis: String, reference: String) -> Double {
        let hypothesisCharacters = Array(hypothesis.filter { !$0.isWhitespace })
        let referenceCharacters = Array(reference.filter { !$0.isWhitespace })
        var precisions: [Double] = []
        var recalls: [Double] = []
        for order in 1...maxOrder {
            let hypothesisGrams = grams(hypothesisCharacters, order)
            let referenceGrams = grams(referenceCharacters, order)
            let hypothesisTotal = hypothesisGrams.values.reduce(0, +)
            let referenceTotal = referenceGrams.values.reduce(0, +)
            if hypothesisTotal == 0 || referenceTotal == 0 { continue }
            let matched = hypothesisGrams.reduce(0) { $0 + min($1.value, referenceGrams[$1.key] ?? 0) }
            precisions.append(Double(matched) / Double(hypothesisTotal))
            recalls.append(Double(matched) / Double(referenceTotal))
        }
        guard !precisions.isEmpty else { return 0 }
        let precision = precisions.reduce(0, +) / Double(precisions.count)
        let recall = recalls.reduce(0, +) / Double(recalls.count)
        let weight = beta * beta
        let denominator = weight * precision + recall
        guard denominator > 0 else { return 0 }
        return 100 * (1 + weight) * precision * recall / denominator
    }

    static func grams(_ characters: [Character], _ order: Int) -> [String: Int] {
        var counts: [String: Int] = [:]
        guard characters.count >= order else { return counts }
        for start in 0...(characters.count - order) {
            counts[String(characters[start..<(start + order)]), default: 0] += 1
        }
        return counts
    }
}
```

- [ ] **Step 4: Run them to verify they pass**

Run: `swift test --filter ChrFTests`
Expected: PASS.

- [ ] **Step 5: Plant two defects and watch them fail**

Revert each before the next.
- Replace `min(` with `max(`. Expected: `clipped` fails.
- Change `let weight = beta * beta` to `let weight = beta`. Expected: `handComputed` fails.

- [ ] **Step 6: Add the file to the mutation list**

Before the `WordDiff.swift"` line:

```
          Sources/BabelOtterKit/Eval/ChrF.swift
```

- [ ] **Step 7: Commit**

```bash
git add Sources/BabelOtterKit/Eval/ChrF.swift Tests/BabelOtterKitTests/Eval/ChrFTests.swift .github/workflows/mutation.yml
git commit -m "feat(eval): chrF, pinned against hand-computed values

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The translation scorer

**Files:**
- Create: `Sources/BabelOtterKit/Eval/TranslationScorer.swift`
- Test: `Tests/BabelOtterKitTests/Eval/TranslationScorerTests.swift`
- Modify: `.github/workflows/mutation.yml`

**Interfaces:**
- Consumes: `TranslationCase`, `TranslationDirection.targetIsGerman` (Task 2); `EvalFailure` (Task 3); `ChrF.score` (Task 4); `StructureExtractor.extract`, `Skeleton.blockCount`, `Skeleton.lines[].marker` (existing; `lines` and `marker` are internal and reachable inside the kit).
- Produces:
  - `public enum TranslationOutcome: Sendable, Equatable { case translated(String), failed(EvalFailure) }`
  - `public struct TranslationScore: Sendable, Equatable, Codable`, with fields:
    - `caseID: String`, `failure: EvalFailure?`;
    - `esszettAbsent: Bool?` (nil when the target is English);
    - `missingTerms: [String]`, `sentinelDebris: Bool`, `structureKept: Bool`;
    - `chrF: Double`;
    - computed `termsKept: Bool`.
  - `public enum TranslationScorer { public static func score(_ testCase: TranslationCase, outcome: TranslationOutcome) -> TranslationScore }`
  - internal: `TranslationScorer.sameStructure(_ source: String, _ output: String) -> Bool`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing

@testable import BabelOtterKit

private func translationCase(
    _ text: String, _ direction: TranslationDirection = .englishToSwissGerman,
    terms: [String] = [], reference: String = "Referenz"
) -> TranslationCase {
    TranslationCase(
        id: "t", text: text, direction: direction, profileID: "colleagues", terms: terms,
        reference: reference)
}

@Suite("Eval: a translation scored against its case")
struct TranslationScorerTests {

    @Test("a German target must contain no eszett; an English one is not checked")
    func esszett() {
        let german = translationCase("Street.")
        #expect(TranslationScorer.score(german, outcome: .translated("Strasse.")).esszettAbsent == true)
        #expect(TranslationScorer.score(german, outcome: .translated("Stra\u{00DF}e.")).esszettAbsent == false)
        let english = translationCase("Strasse.", .swissGermanToEnglish)
        #expect(TranslationScorer.score(english, outcome: .translated("Street.")).esszettAbsent == nil)
    }

    @Test("every term must come back verbatim")
    func terms() {
        let theCase = translationCase("Meet Otterbach at Riverside.", terms: ["Otterbach", "Riverside"],
                                      reference: "Otterbach Riverside")
        let score = TranslationScorer.score(theCase, outcome: .translated("Treffen Sie Otterbach am Fluss."))
        #expect(score.missingTerms == ["Riverside"])
        #expect(!score.termsKept)
        let kept = TranslationScorer.score(theCase, outcome: .translated("Otterbach bei Riverside."))
        #expect(kept.termsKept)
    }

    @Test("a sentinel bracket left in the output fails the terms check")
    func sentinelDebris() {
        let theCase = translationCase("Hello.")
        let score = TranslationScorer.score(theCase, outcome: .translated("Hallo \u{27E6}DNT0\u{27E7}."))
        #expect(score.sentinelDebris)
        #expect(!score.termsKept)
        #expect(TranslationScorer.score(theCase, outcome: .translated("Hallo \u{27E7}")).sentinelDebris)
        #expect(!TranslationScorer.score(theCase, outcome: .translated("Hallo.")).sentinelDebris)
    }

    @Test("structure is the same block count and list markers", arguments: [
        ("- one\n- two", "- eins\n- zwei", true),
        ("- one\n- two", "eins und zwei", false),
        ("One.\n\nTwo.", "Eins.\n\nZwei.", true),
        ("One.\n\nTwo.", "Eins. Zwei.", false),
        ("1. one\n2. two", "- eins\n- zwei", false),
    ])
    func structure(source: String, output: String, kept: Bool) {
        #expect(TranslationScorer.sameStructure(source, output) == kept)
    }

    @Test("chrF is taken against the reference")
    func similarity() {
        let theCase = translationCase("Good morning.", reference: "Guten Morgen.")
        #expect(TranslationScorer.score(theCase, outcome: .translated("Guten Morgen.")).chrF > 99.9)
        #expect(TranslationScorer.score(theCase, outcome: .translated("xyz")).chrF == 0)
    }

    @Test("a failed translation fails every check")
    func failed() {
        let theCase = translationCase("Hi Otterbach.", terms: ["Otterbach"], reference: "Hallo Otterbach.")
        let score = TranslationScorer.score(theCase, outcome: .failed(.timeout))
        #expect(score.failure == .timeout)
        #expect(score.esszettAbsent == false)
        #expect(score.missingTerms == ["Otterbach"])
        #expect(!score.structureKept)
        #expect(score.chrF == 0)
        let english = translationCase("Hallo.", .swissGermanToEnglish, reference: "Hello.")
        #expect(TranslationScorer.score(english, outcome: .failed(.other)).esszettAbsent == nil)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter TranslationScorerTests`
Expected: FAIL to compile, "cannot find 'TranslationScorer' in scope".

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public enum TranslationOutcome: Sendable, Equatable {
    /// The finished translation's text.
    case translated(String)
    case failed(EvalFailure)
}

public struct TranslationScore: Sendable, Equatable, Codable {
    public let caseID: String
    public let failure: EvalFailure?
    /// Nil when the target is not German.
    public let esszettAbsent: Bool?
    public let missingTerms: [String]
    public let sentinelDebris: Bool
    public let structureKept: Bool
    public let chrF: Double

    public var termsKept: Bool { missingTerms.isEmpty && !sentinelDebris }
}

/// One translation scored against its case (spec 2026-09-30, section 4.3).
public enum TranslationScorer {

    static let esszett = "\u{00DF}"
    static let sentinelBrackets = ["\u{27E6}", "\u{27E7}"]

    public static func score(_ testCase: TranslationCase, outcome: TranslationOutcome) -> TranslationScore {
        switch outcome {
        case .failed(let failure):
            return TranslationScore(
                caseID: testCase.id, failure: failure,
                esszettAbsent: germanCheck(testCase, passed: false), missingTerms: testCase.terms,
                sentinelDebris: false, structureKept: false, chrF: 0)
        case .translated(let output):
            return TranslationScore(
                caseID: testCase.id, failure: nil,
                esszettAbsent: germanCheck(testCase, passed: !output.contains(esszett)),
                missingTerms: testCase.terms.filter { !output.contains($0) },
                sentinelDebris: sentinelBrackets.contains { output.contains($0) },
                structureKept: sameStructure(testCase.text, output),
                chrF: ChrF.score(hypothesis: output, reference: testCase.reference))
        }
    }

    private static func germanCheck(_ testCase: TranslationCase, passed: Bool) -> Bool? {
        guard testCase.direction.targetIsGerman else { return nil }
        return passed
    }

    /// The same number of blocks and the same list markers, in order.
    static func sameStructure(_ source: String, _ output: String) -> Bool {
        let before = StructureExtractor.extract(source).skeleton
        let after = StructureExtractor.extract(output).skeleton
        return before.blockCount == after.blockCount && markers(before) == markers(after)
    }

    private static func markers(_ skeleton: Skeleton) -> [String] {
        skeleton.lines
            .map { $0.marker.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
```

- [ ] **Step 4: Run them to verify they pass**

Run: `swift test --filter TranslationScorerTests`
Expected: PASS. `StructureExtractor` treats `-`, `*` and `1.`/`1)` as markers, so the bullet-versus-numbered row is a real structure change.

- [ ] **Step 5: Plant two defects and watch them fail**

Revert each before the next.
- Change `&& markers(before) == markers(after)` to nothing (block count only). Expected: the bullet-versus-numbered row fails.
- In the `.failed` case, set `missingTerms: []`. Expected: `failed` fails.

- [ ] **Step 6: Add the file to the mutation list**

Before the `WordDiff.swift"` line:

```
          Sources/BabelOtterKit/Eval/TranslationScorer.swift
```

- [ ] **Step 7: Commit**

```bash
git add Sources/BabelOtterKit/Eval/TranslationScorer.swift Tests/BabelOtterKitTests/Eval/TranslationScorerTests.swift .github/workflows/mutation.yml
git commit -m "feat(eval): score a translation against its case

Eszett absence for de-CH, terms verbatim and no sentinel debris,
structure by block count and markers, and chrF.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Summaries, metrics and deltas

**Files:**
- Create: `Sources/BabelOtterKit/Eval/EvalSummary.swift`
- Test: `Tests/BabelOtterKitTests/Eval/EvalSummaryTests.swift`
- Modify: `.github/workflows/mutation.yml`

**Interfaces:**
- Consumes: `CorrectionScore` (Task 3), `TranslationScore` (Task 5).
- Produces:
  - `public enum MetricKind: String, Codable { case rate, count, seconds, score }`
  - `public struct Metric: Sendable, Equatable, Codable { name: String; value: Double; kind: MetricKind; higherIsBetter: Bool }`
  - `public struct MetricDelta: Sendable, Equatable { name; kind; before: Double; after: Double; higherIsBetter; var change: Double }`
  - `public protocol EvalSummary: Sendable { var model: String { get }; var metrics: [Metric] { get } }`, extended with `public func delta(from earlier: some EvalSummary) -> [MetricDelta]`
  - `public struct Latency: Sendable, Equatable, Codable { median: Double; max: Double }`, with `public init(seconds: [Double])`
  - `public struct CorrectionSummary: EvalSummary, Equatable, Codable`:
    - `public init(model: String, scores: [CorrectionScore], seconds: [Double])`;
    - fields `model`, `cases: Int`, `meanRecall`, `overCorrectedWords: Int`, `overCorrectionRate`, `guardViolations: Int`, `categoryAccuracy`, `cleanPassRate`, `failures: [String: Int]`, `warnings: Int`, `latency`.
  - `public struct TranslationSummary: EvalSummary, Equatable, Codable`:
    - `public init(model: String, scores: [TranslationScore], seconds: [Double])`;
    - fields `model`, `cases`, `esszettPassRate`, `termPassRate`, `structurePassRate`, `meanChrF`, `failures`, `latency`.

Aggregation rules:

- **Correction:**
  - `meanRecall` is the mean of `recall` over scores that have one; a failure's recall is 0.
  - Over-correction sums `overCorrectedWords` and `originalWords` over scores without a failure; the rate is their ratio.
  - `categoryAccuracy = sum(categoryMatches) / sum(foundFixes)`.
  - `cleanPassRate` is computed over scores where `cleanPassed != nil`.
  - `failures` counts by `EvalFailure.rawValue`.
- **Translation:**
  - `esszettPassRate` is computed over scores where `esszettAbsent != nil`.
  - `termPassRate` and `structurePassRate` are computed over all scores, failures included as fails.
  - `meanChrF` is the mean over all scores, failures counting 0.
- **Both:**
  - Any rate with an empty denominator is 0.
  - `Latency`: median of the sorted seconds (the mean of the middle two for an even count), and the max; both 0 when there are no seconds.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing

@testable import BabelOtterKit

private func correctionScore(
    expected: Int = 0, missed: Int = 0, over: Int = 0, words: Int = 10, guards: [String] = [],
    matches: Int = 0, unexplained: Int = 0, clean: Bool? = nil, warnings: Int = 0,
    failure: EvalFailure? = nil
) -> CorrectionScore {
    CorrectionScore(
        caseID: "c", failure: failure, expectedFixes: expected,
        missedFixes: Array(repeating: "w", count: missed), overCorrectedWords: over,
        originalWords: words, guardViolations: guards, categoryMatches: matches,
        unexplainedFixes: unexplained, cleanPassed: clean, warnings: warnings)
}

private func translationScore(
    esszett: Bool? = true, missing: [String] = [], debris: Bool = false, structure: Bool = true,
    chrF: Double = 50, failure: EvalFailure? = nil
) -> TranslationScore {
    TranslationScore(
        caseID: "t", failure: failure, esszettAbsent: esszett, missingTerms: missing,
        sentinelDebris: debris, structureKept: structure, chrF: chrF)
}

private func close(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 0.0001 }

@Suite("Eval: summaries and deltas")
struct EvalSummaryTests {

    private let scores = [
        correctionScore(expected: 2, missed: 1, over: 1, words: 10, matches: 1, warnings: 1),
        correctionScore(expected: 1, missed: 0, over: 0, words: 10, guards: ["Kollegin"], unexplained: 1),
        correctionScore(clean: true),
        correctionScore(expected: 1, missed: 1, over: 4, words: 5, failure: .timeout),
    ]

    @Test("correction metrics aggregate as specified")
    func correction() {
        let summary = CorrectionSummary(model: "m", scores: scores, seconds: [1, 3, 2, 10])
        #expect(summary.cases == 4)
        #expect(close(summary.meanRecall, 0.5))
        #expect(summary.overCorrectedWords == 1)
        #expect(close(summary.overCorrectionRate, 1.0 / 30.0))
        #expect(summary.guardViolations == 1)
        #expect(close(summary.categoryAccuracy, 0.5))
        #expect(close(summary.cleanPassRate, 1))
        #expect(summary.failures == ["timeout": 1])
        #expect(summary.warnings == 1)
        #expect(summary.latency == Latency(median: 2.5, max: 10))
    }

    @Test("rates with nothing to measure are 0")
    func emptyRates() {
        let summary = CorrectionSummary(model: "m", scores: [], seconds: [])
        #expect(summary.meanRecall == 0)
        #expect(summary.overCorrectionRate == 0)
        #expect(summary.categoryAccuracy == 0)
        #expect(summary.cleanPassRate == 0)
        #expect(summary.latency == Latency(median: 0, max: 0))
    }

    @Test("latency median of an odd count is the middle value")
    func oddMedian() {
        #expect(Latency(seconds: [5, 1, 3]) == Latency(median: 3, max: 5))
    }

    @Test("translation metrics aggregate as specified")
    func translation() {
        let summary = TranslationSummary(model: "m", scores: [
            translationScore(esszett: true, chrF: 80),
            translationScore(esszett: nil, missing: ["X"], structure: false, chrF: 40),
            translationScore(esszett: false, debris: true, chrF: 0, failure: .other),
        ], seconds: [2, 4, 6])
        #expect(summary.cases == 3)
        #expect(close(summary.esszettPassRate, 0.5))
        #expect(close(summary.termPassRate, 1.0 / 3.0))
        #expect(close(summary.structurePassRate, 2.0 / 3.0))
        #expect(close(summary.meanChrF, 40))
        #expect(summary.failures == ["other": 1])
        #expect(summary.latency == Latency(median: 4, max: 6))
    }

    @Test("metrics are listed in a fixed order with their direction")
    func metricNames() {
        let correction = CorrectionSummary(model: "m", scores: scores, seconds: [1])
        #expect(correction.metrics.map(\.name) == [
            "recall", "over-correction", "over-corrected words", "guard violations",
            "category accuracy", "clean pass", "failures", "warnings", "latency median", "latency max",
        ])
        #expect(correction.metrics.first?.higherIsBetter == true)
        #expect(correction.metrics[1].higherIsBetter == false)
        #expect(correction.metrics.first(where: { $0.name == "failures" })?.value == 1)
        let translation = TranslationSummary(model: "m", scores: [], seconds: [])
        #expect(translation.metrics.map(\.name) == [
            "no eszett", "terms kept", "structure kept", "chrF", "failures", "latency median", "latency max",
        ])
    }

    @Test("a delta pairs metrics by name and skips ones the earlier run lacks")
    func delta() {
        let before = CorrectionSummary(model: "m", scores: [correctionScore(expected: 2, missed: 2)], seconds: [1])
        let after = CorrectionSummary(model: "m", scores: [correctionScore(expected: 2, missed: 0)], seconds: [3])
        let deltas = after.delta(from: before)
        let recall = deltas.first { $0.name == "recall" }
        #expect(recall?.before == 0)
        #expect(recall?.after == 1)
        #expect(recall?.change == 1)
        #expect(deltas.first { $0.name == "latency median" }?.change == 2)
        #expect(deltas.count == after.metrics.count)

        let translation = TranslationSummary(model: "m", scores: [], seconds: [])
        let across = after.delta(from: translation)
        #expect(across.map(\.name) == ["failures", "latency median", "latency max"])
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter EvalSummaryTests`
Expected: FAIL to compile, "cannot find 'CorrectionSummary' in scope".

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public enum MetricKind: String, Sendable, Codable {
    case rate
    case count
    case seconds
    case score
}

public struct Metric: Sendable, Equatable, Codable {
    public let name: String
    public let value: Double
    public let kind: MetricKind
    public let higherIsBetter: Bool
}

public struct MetricDelta: Sendable, Equatable {
    public let name: String
    public let kind: MetricKind
    public let before: Double
    public let after: Double
    public let higherIsBetter: Bool

    public var change: Double { after - before }
}

/// One model's aggregate over a run, as named metrics in a fixed order.
public protocol EvalSummary: Sendable {
    var model: String { get }
    var metrics: [Metric] { get }
}

extension EvalSummary {
    /// Changes against an earlier summary, metric by metric. A metric the
    /// earlier summary lacks is skipped rather than compared with zero.
    public func delta(from earlier: some EvalSummary) -> [MetricDelta] {
        metrics.compactMap { metric in
            guard let before = earlier.metrics.first(where: { $0.name == metric.name }) else { return nil }
            return MetricDelta(
                name: metric.name, kind: metric.kind, before: before.value, after: metric.value,
                higherIsBetter: metric.higherIsBetter)
        }
    }
}

public struct Latency: Sendable, Equatable, Codable {
    public let median: Double
    public let max: Double

    init(median: Double, max: Double) {
        self.median = median
        self.max = max
    }

    public init(seconds: [Double]) {
        let sorted = seconds.sorted()
        guard let last = sorted.last else {
            self.init(median: 0, max: 0)
            return
        }
        let middle = sorted.count / 2
        let median = sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        self.init(median: median, max: last)
    }
}

/// A ratio that is 0, not NaN, when there is nothing to measure.
func ratio(_ numerator: Double, _ denominator: Double) -> Double {
    guard denominator > 0 else { return 0 }
    return numerator / denominator
}

func failureCounts(_ failures: [EvalFailure?]) -> [String: Int] {
    var counts: [String: Int] = [:]
    for case let failure? in failures {
        counts[failure.rawValue, default: 0] += 1
    }
    return counts
}

public struct CorrectionSummary: EvalSummary, Equatable, Codable {
    public let model: String
    public let cases: Int
    public let meanRecall: Double
    public let overCorrectedWords: Int
    public let overCorrectionRate: Double
    public let guardViolations: Int
    public let categoryAccuracy: Double
    public let cleanPassRate: Double
    public let failures: [String: Int]
    public let warnings: Int
    public let latency: Latency

    public init(model: String, scores: [CorrectionScore], seconds: [Double]) {
        self.model = model
        cases = scores.count
        let recalls = scores.compactMap(\.recall)
        meanRecall = ratio(recalls.reduce(0, +), Double(recalls.count))
        let answered = scores.filter { $0.failure == nil }
        overCorrectedWords = answered.reduce(0) { $0 + $1.overCorrectedWords }
        overCorrectionRate = ratio(
            Double(overCorrectedWords), Double(answered.reduce(0) { $0 + $1.originalWords }))
        guardViolations = scores.reduce(0) { $0 + $1.guardViolations.count }
        categoryAccuracy = ratio(
            Double(scores.reduce(0) { $0 + $1.categoryMatches }),
            Double(scores.reduce(0) { $0 + $1.foundFixes }))
        let cleanVerdicts = scores.compactMap(\.cleanPassed)
        cleanPassRate = ratio(Double(cleanVerdicts.filter { $0 }.count), Double(cleanVerdicts.count))
        failures = failureCounts(scores.map(\.failure))
        warnings = scores.reduce(0) { $0 + $1.warnings }
        latency = Latency(seconds: seconds)
    }

    public var metrics: [Metric] {
        [
            Metric(name: "recall", value: meanRecall, kind: .rate, higherIsBetter: true),
            Metric(name: "over-correction", value: overCorrectionRate, kind: .rate, higherIsBetter: false),
            Metric(name: "over-corrected words", value: Double(overCorrectedWords), kind: .count, higherIsBetter: false),
            Metric(name: "guard violations", value: Double(guardViolations), kind: .count, higherIsBetter: false),
            Metric(name: "category accuracy", value: categoryAccuracy, kind: .rate, higherIsBetter: true),
            Metric(name: "clean pass", value: cleanPassRate, kind: .rate, higherIsBetter: true),
            Metric(name: "failures", value: Double(failures.values.reduce(0, +)), kind: .count, higherIsBetter: false),
            Metric(name: "warnings", value: Double(warnings), kind: .count, higherIsBetter: false),
            Metric(name: "latency median", value: latency.median, kind: .seconds, higherIsBetter: false),
            Metric(name: "latency max", value: latency.max, kind: .seconds, higherIsBetter: false),
        ]
    }
}

public struct TranslationSummary: EvalSummary, Equatable, Codable {
    public let model: String
    public let cases: Int
    public let esszettPassRate: Double
    public let termPassRate: Double
    public let structurePassRate: Double
    public let meanChrF: Double
    public let failures: [String: Int]
    public let latency: Latency

    public init(model: String, scores: [TranslationScore], seconds: [Double]) {
        self.model = model
        cases = scores.count
        let esszettVerdicts = scores.compactMap(\.esszettAbsent)
        esszettPassRate = ratio(Double(esszettVerdicts.filter { $0 }.count), Double(esszettVerdicts.count))
        termPassRate = ratio(Double(scores.filter(\.termsKept).count), Double(scores.count))
        structurePassRate = ratio(Double(scores.filter(\.structureKept).count), Double(scores.count))
        meanChrF = ratio(scores.reduce(0) { $0 + $1.chrF }, Double(scores.count))
        failures = failureCounts(scores.map(\.failure))
        latency = Latency(seconds: seconds)
    }

    public var metrics: [Metric] {
        [
            Metric(name: "no eszett", value: esszettPassRate, kind: .rate, higherIsBetter: true),
            Metric(name: "terms kept", value: termPassRate, kind: .rate, higherIsBetter: true),
            Metric(name: "structure kept", value: structurePassRate, kind: .rate, higherIsBetter: true),
            Metric(name: "chrF", value: meanChrF, kind: .score, higherIsBetter: true),
            Metric(name: "failures", value: Double(failures.values.reduce(0, +)), kind: .count, higherIsBetter: false),
            Metric(name: "latency median", value: latency.median, kind: .seconds, higherIsBetter: false),
            Metric(name: "latency max", value: latency.max, kind: .seconds, higherIsBetter: false),
        ]
    }
}
```

The `Latency` median ternary's condition ends in `== 0`, not in an enum member, so the muter trap doesn't apply.

- [ ] **Step 4: Run them to verify they pass**

Run: `swift test --filter EvalSummaryTests`
Expected: PASS.

- [ ] **Step 5: Plant two defects and watch them fail**

Revert each before the next.
- Change `let answered = scores.filter { $0.failure == nil }` to `let answered = scores`. Expected: `correction` fails (rate 5/35, words 5).
- In `Latency`, replace the even branch with `sorted[middle]`. Expected: `correction` fails (median 3).

- [ ] **Step 6: Add the file to the mutation list**

Before the `WordDiff.swift"` line:

```
          Sources/BabelOtterKit/Eval/EvalSummary.swift
```

- [ ] **Step 7: Commit**

```bash
git add Sources/BabelOtterKit/Eval/EvalSummary.swift Tests/BabelOtterKitTests/Eval/EvalSummaryTests.swift .github/workflows/mutation.yml
git commit -m "feat(eval): per-model summaries as named metrics, with deltas

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Arguments and case selection

**Files:**
- Create: `Sources/BabelOtterKit/Eval/EvalArguments.swift`
- Test: `Tests/BabelOtterKitTests/Eval/EvalArgumentsTests.swift`
- Modify: `.github/workflows/mutation.yml`

**Interfaces:**
- Consumes: `GoldenSet`, `CorrectionCase`, `TranslationCase` (Task 2).
- Produces:
  - `public enum EvalSelection: Sendable, Equatable { case everything, correctionOnly, translationOnly, cases([String]) }`
  - `public struct EvalArguments: Sendable, Equatable`:
    - fields `models: [String]?`, `selection: EvalSelection`, `repeatCount: Int`, `compare: String?`;
    - `public static func parse(_ arguments: [String]) throws -> EvalArguments` (arguments exclude the program name);
    - `public func cases(from golden: GoldenSet) throws -> (correction: [CorrectionCase], translation: [TranslationCase])`.
  - `public struct EvalArgumentError: Error, Equatable, CustomStringConvertible { message: String }`

- [ ] **Step 1: Write the failing tests**

```swift
import Testing

@testable import BabelOtterKit

private let golden = GoldenSet(
    correction: [
        CorrectionCase(id: "c1", text: "a", profileID: "colleagues", terms: [], fixes: [], mustNot: [], clean: true),
        CorrectionCase(id: "c2", text: "b", profileID: "colleagues", terms: [], fixes: [], mustNot: [], clean: true),
    ],
    translation: [
        TranslationCase(id: "t1", text: "c", direction: .englishToSwissGerman, profileID: "colleagues", terms: [], reference: "d"),
    ])

@Suite("Eval: arguments and case selection")
struct EvalArgumentsTests {

    @Test("no arguments means every model, every case, one run")
    func defaults() throws {
        let parsed = try EvalArguments.parse([])
        #expect(parsed == EvalArguments(models: nil, selection: .everything, repeatCount: 1, compare: nil))
    }

    @Test("every option is read")
    func everyOption() throws {
        let parsed = try EvalArguments.parse([
            "--models", "a:1, b:2", "--only", "c1,t1", "--repeat", "3", "--compare", "evals/results/x.json",
        ])
        #expect(parsed.models == ["a:1", "b:2"])
        #expect(parsed.selection == .cases(["c1", "t1"]))
        #expect(parsed.repeatCount == 3)
        #expect(parsed.compare == "evals/results/x.json")
    }

    @Test("--only takes an action name")
    func onlyAction() throws {
        #expect(try EvalArguments.parse(["--only", "correct"]).selection == .correctionOnly)
        #expect(try EvalArguments.parse(["--only", "translate"]).selection == .translationOnly)
    }

    @Test("bad arguments are refused with a reason", arguments: [
        ["--model", "a"],
        ["--models"],
        ["--models", "--only", "correct"],
        ["--models", " , "],
        ["--repeat", "0"],
        ["--repeat", "two"],
        ["--only", "correct", "--only", "translate"],
        ["stray"],
    ])
    func refused(arguments: [String]) {
        #expect(throws: EvalArgumentError.self) { try EvalArguments.parse(arguments) }
    }

    @Test("selection picks the cases it names")
    func selection() throws {
        let all = try EvalArguments(models: nil, selection: .everything, repeatCount: 1, compare: nil).cases(from: golden)
        #expect(all.correction.map(\.id) == ["c1", "c2"])
        #expect(all.translation.map(\.id) == ["t1"])
        let correctOnly = try EvalArguments(models: nil, selection: .correctionOnly, repeatCount: 1, compare: nil).cases(from: golden)
        #expect(correctOnly.translation.isEmpty)
        #expect(correctOnly.correction.count == 2)
        let translateOnly = try EvalArguments(models: nil, selection: .translationOnly, repeatCount: 1, compare: nil).cases(from: golden)
        #expect(translateOnly.correction.isEmpty)
        #expect(translateOnly.translation.count == 1)
        let named = try EvalArguments(models: nil, selection: .cases(["c2", "t1"]), repeatCount: 1, compare: nil).cases(from: golden)
        #expect(named.correction.map(\.id) == ["c2"])
        #expect(named.translation.map(\.id) == ["t1"])
    }

    @Test("a mistyped case id is an error naming it, never an empty run")
    func unknownCase() {
        let arguments = EvalArguments(models: nil, selection: .cases(["c1", "c9"]), repeatCount: 1, compare: nil)
        #expect(throws: EvalArgumentError(message: "no case named c9")) { try arguments.cases(from: golden) }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter EvalArgumentsTests`
Expected: FAIL to compile, "cannot find 'EvalArguments' in scope".

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public enum EvalSelection: Sendable, Equatable {
    case everything
    case correctionOnly
    case translationOnly
    case cases([String])
}

public struct EvalArgumentError: Error, Equatable, CustomStringConvertible {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// `babelotter-eval [--models a,b] [--only correct|translate|<id>,...]
/// [--repeat N] [--compare <file>]`, parsed (spec 2026-09-30, section 5).
public struct EvalArguments: Sendable, Equatable {
    public var models: [String]?
    public var selection: EvalSelection
    public var repeatCount: Int
    public var compare: String?

    static let flags = ["--models", "--only", "--repeat", "--compare"]

    public static func parse(_ arguments: [String]) throws -> EvalArguments {
        var parsed = EvalArguments(models: nil, selection: .everything, repeatCount: 1, compare: nil)
        var seen: Set<String> = []
        var remaining = arguments[...]
        while let flag = remaining.popFirst() {
            guard flags.contains(flag) else { throw EvalArgumentError(message: "unknown option \(flag)") }
            guard seen.insert(flag).inserted else { throw EvalArgumentError(message: "\(flag) given twice") }
            guard let value = remaining.popFirst(), !value.hasPrefix("--") else {
                throw EvalArgumentError(message: "\(flag) needs a value")
            }
            try parsed.apply(flag, value)
        }
        return parsed
    }

    private mutating func apply(_ flag: String, _ value: String) throws {
        switch flag {
        case "--models":
            models = try Self.list(value, flag)
        case "--only":
            selection = try Self.selection(value)
        case "--repeat":
            guard let count = Int(value), count >= 1 else {
                throw EvalArgumentError(message: "--repeat needs a whole number of at least 1, not \(value)")
            }
            repeatCount = count
        default:
            compare = value
        }
    }

    private static func selection(_ value: String) throws -> EvalSelection {
        switch value {
        case "correct": return .correctionOnly
        case "translate": return .translationOnly
        default: return .cases(try list(value, "--only"))
        }
    }

    private static func list(_ value: String, _ flag: String) throws -> [String] {
        let items = value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !items.isEmpty else { throw EvalArgumentError(message: "\(flag) needs at least one name") }
        return items
    }

    public func cases(from golden: GoldenSet) throws -> (correction: [CorrectionCase], translation: [TranslationCase]) {
        switch selection {
        case .everything:
            return (golden.correction, golden.translation)
        case .correctionOnly:
            return (golden.correction, [])
        case .translationOnly:
            return ([], golden.translation)
        case .cases(let ids):
            let known = Set(golden.correction.map(\.id) + golden.translation.map(\.id))
            let unknown = ids.filter { !known.contains($0) }
            guard unknown.isEmpty else {
                throw EvalArgumentError(message: "no case named \(unknown.joined(separator: ", "))")
            }
            return (golden.correction.filter { ids.contains($0.id) }, golden.translation.filter { ids.contains($0.id) })
        }
    }
}
```

`EvalArguments(models:selection:repeatCount:compare:)` is the internal memberwise init. The CLI only calls `parse`, so it needs no public init.

- [ ] **Step 4: Run them to verify they pass**

Run: `swift test --filter EvalArgumentsTests`
Expected: PASS.

- [ ] **Step 5: Plant a defect and watch it fail**

Delete the `guard unknown.isEmpty` check. Expected: `unknownCase` fails. Revert.

- [ ] **Step 6: Add the file to the mutation list**

Before the `WordDiff.swift"` line:

```
          Sources/BabelOtterKit/Eval/EvalArguments.swift
```

- [ ] **Step 7: Commit**

```bash
git add Sources/BabelOtterKit/Eval/EvalArguments.swift Tests/BabelOtterKitTests/Eval/EvalArgumentsTests.swift .github/workflows/mutation.yml
git commit -m "feat(eval): parse arguments and select cases

A mistyped case id is an error, never an empty run.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: The saved run and the report text

**Files:**
- Create: `Sources/BabelOtterKit/Eval/EvalRun.swift`
- Create: `Sources/BabelOtterKit/Eval/EvalReport.swift`
- Test: `Tests/BabelOtterKitTests/Eval/EvalRunTests.swift`
- Test: `Tests/BabelOtterKitTests/Eval/EvalReportTests.swift`
- Modify: `.github/workflows/mutation.yml`

**Interfaces:**
- Consumes: everything from Tasks 2-6.
- Produces:
  - `public struct CaseRecord: Sendable, Equatable, Codable`:
    - `public init(model:caseID:run:seconds:output:failureDetail:correction:translation:)`;
    - fields `model: String`, `caseID: String`, `run: Int`, `seconds: Double`, `output: String?`, `failureDetail: String?`, `correction: CorrectionScore?`, `translation: TranslationScore?`.
  - `public struct EvalRun: Sendable, Equatable, Codable`:
    - `public init(startedAt:commit:correction:translation:records:)`;
    - fields `startedAt: Date`, `commit: String`, `correction: [CorrectionSummary]`, `translation: [TranslationSummary]`, `records: [CaseRecord]`;
    - `public func encoded() throws -> Data`, `public static func decode(_ data: Data) throws -> EvalRun`;
    - `public static func fileName(startedAt: Date, commit: String, timeZone: TimeZone = .current) -> String`.
  - `public enum EvalReport`:
    - `static func table<S: EvalSummary>(_ title: String, _ summaries: [S], baseline: [S]) -> String`;
    - `static func correctionMisses(model: String, testCase: CorrectionCase, score: CorrectionScore) -> [String]`;
    - `static func translationMisses(model: String, testCase: TranslationCase, score: TranslationScore) -> [String]`;
    - `static func format(_ value: Double, _ kind: MetricKind) -> String`;
    - `static func signedChange(_ change: Double, _ kind: MetricKind) -> String`.

    All of them are `public`.

Table layout: one row per metric and one column per model, because a run has about ten metrics and few models. Under `--compare`, a cell becomes `value (change)` when the baseline has that model and that metric. Formats:

| Kind | Value | Change |
|---|---|---|
| rate | `82.0%` | `+3.0pp` |
| count | `3` | `+1` |
| seconds | `6.2s` | `+0.4s` |
| score | `54.3` | `+1.2` |

- [ ] **Step 1: Write the failing tests**

`Tests/BabelOtterKitTests/Eval/EvalRunTests.swift`:

```swift
import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Eval: the saved run")
struct EvalRunTests {

    @Test("a run survives encoding and decoding")
    func roundTrip() throws {
        let score = CorrectionScore(
            caseID: "c", failure: nil, expectedFixes: 1, missedFixes: [], overCorrectedWords: 0,
            originalWords: 4, guardViolations: [], categoryMatches: 1, unexplainedFixes: 0,
            cleanPassed: nil, warnings: 0)
        let run = EvalRun(
            startedAt: Date(timeIntervalSince1970: 1_790_000_000), commit: "abc1234",
            correction: [CorrectionSummary(model: "m", scores: [score], seconds: [2])],
            translation: [],
            records: [CaseRecord(
                model: "m", caseID: "c", run: 1, seconds: 2, output: "Ich bin jetzt da.",
                failureDetail: nil, correction: score, translation: nil)])
        #expect(try EvalRun.decode(run.encoded()) == run)
    }

    @Test("the file name is the start time and the commit")
    func fileName() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21 14:13 UTC
        #expect(EvalRun.fileName(startedAt: date, commit: "abc1234", timeZone: utc)
            == "2026-09-21-1413-abc1234.json")
    }
}
```

Before writing the expected file name, check the date: `date -u -r 1790000000 +%Y-%m-%d-%H%M`. If it prints something other than `2026-09-21-1413`, use what it prints in both the comment and the expectation.

`Tests/BabelOtterKitTests/Eval/EvalReportTests.swift`:

```swift
import Testing

@testable import BabelOtterKit

private func correctionScore(expected: Int, missed: [String] = [], guards: [String] = [],
                             clean: Bool? = nil, failure: EvalFailure? = nil) -> CorrectionScore {
    CorrectionScore(
        caseID: "c", failure: failure, expectedFixes: expected, missedFixes: missed,
        overCorrectedWords: 0, originalWords: 10, guardViolations: guards, categoryMatches: 0,
        unexplainedFixes: 0, cleanPassed: clean, warnings: 0)
}

@Suite("Eval: the report")
struct EvalReportTests {

    @Test("values and changes are formatted by kind", arguments: [
        (0.82, MetricKind.rate, "82.0%", "+82.0pp"),
        (3.0, MetricKind.count, "3", "+3"),
        (6.25, MetricKind.seconds, "6.2s", "+6.2s"),
        (54.31, MetricKind.score, "54.3", "+54.3"),
    ])
    func formatting(value: Double, kind: MetricKind, formatted: String, change: String) {
        #expect(EvalReport.format(value, kind) == formatted)
        #expect(EvalReport.signedChange(value, kind) == change)
        #expect(EvalReport.signedChange(-value, kind).hasPrefix("-"))
    }

    @Test("the table has a row per metric and a column per model")
    func table() {
        let a = CorrectionSummary(model: "alpha", scores: [correctionScore(expected: 2, missed: ["x"])], seconds: [1])
        let b = CorrectionSummary(model: "beta", scores: [correctionScore(expected: 2)], seconds: [2])
        let lines = EvalReport.table("Correction", [a, b], baseline: []).split(separator: "\n").map(String.init)
        #expect(lines[0] == "Correction")
        #expect(lines[1].hasPrefix("metric"))
        #expect(lines[1].contains("alpha") && lines[1].contains("beta"))
        let recall = lines.first { $0.hasPrefix("recall ") }
        #expect(recall?.contains("50.0%") == true)
        #expect(recall?.contains("100.0%") == true)
        #expect(lines.count == 2 + a.metrics.count)
    }

    @Test("a baseline adds changes only for the models it has")
    func baseline() {
        let before = CorrectionSummary(model: "alpha", scores: [correctionScore(expected: 2, missed: ["x", "y"])], seconds: [1])
        let alpha = CorrectionSummary(model: "alpha", scores: [correctionScore(expected: 2, missed: ["x"])], seconds: [1])
        let gamma = CorrectionSummary(model: "gamma", scores: [correctionScore(expected: 2)], seconds: [1])
        let text = EvalReport.table("Correction", [alpha, gamma], baseline: [before])
        let recall = text.split(separator: "\n").first { $0.hasPrefix("recall ") }.map(String.init)
        #expect(recall?.contains("50.0% (+50.0pp)") == true)
        #expect(recall?.contains("100.0% (") == false)
    }

    @Test("an empty summary list renders nothing")
    func empty() {
        #expect(EvalReport.table("Correction", [CorrectionSummary](), baseline: []).isEmpty)
    }

    @Test("correction misses name each missed fix, guard and clean failure")
    func correctionMisses() {
        let theCase = CorrectionCase(
            id: "jetz", text: "Ich bin jetz da.", profileID: "colleagues", terms: [],
            fixes: [ExpectedFix(wrong: "jetz", right: ["jetzt"], category: .spelling)],
            mustNot: ["Kollegin"], clean: false)
        let lines = EvalReport.correctionMisses(
            model: "m", testCase: theCase,
            score: correctionScore(expected: 1, missed: ["jetz"], guards: ["Kollegin"]))
        #expect(lines == [
            #"m  jetz: missed "jetz" (expected "jetzt")"#,
            #"m  jetz: must not contain "Kollegin""#,
        ])
        let clean = CorrectionCase(id: "ok", text: "Gut.", profileID: "colleagues", terms: [], fixes: [], mustNot: [], clean: true)
        #expect(EvalReport.correctionMisses(model: "m", testCase: clean, score: correctionScore(expected: 0, clean: false))
            == ["m  ok: the clean text was changed or flagged"])
        #expect(EvalReport.correctionMisses(model: "m", testCase: clean, score: correctionScore(expected: 0, clean: true)).isEmpty)
        #expect(EvalReport.correctionMisses(model: "m", testCase: theCase, score: correctionScore(expected: 1, missed: ["jetz"], failure: .timeout))
            == ["m  jetz: failed (timeout)"])
    }

    @Test("translation misses name each failed check")
    func translationMisses() {
        let theCase = TranslationCase(
            id: "t", text: "- Hi Otterbach", direction: .englishToSwissGerman, profileID: "colleagues",
            terms: ["Otterbach"], reference: "- Hallo Otterbach")
        let bad = TranslationScore(
            caseID: "t", failure: nil, esszettAbsent: false, missingTerms: ["Otterbach"],
            sentinelDebris: true, structureKept: false, chrF: 10)
        #expect(EvalReport.translationMisses(model: "m", testCase: theCase, score: bad) == [
            "m  t: contains an eszett",
            #"m  t: term "Otterbach" not kept"#,
            "m  t: a placeholder was left in the output",
            "m  t: structure changed",
        ])
        let good = TranslationScore(
            caseID: "t", failure: nil, esszettAbsent: true, missingTerms: [],
            sentinelDebris: false, structureKept: true, chrF: 90)
        #expect(EvalReport.translationMisses(model: "m", testCase: theCase, score: good).isEmpty)
        let failed = TranslationScore(
            caseID: "t", failure: .other, esszettAbsent: false, missingTerms: ["Otterbach"],
            sentinelDebris: false, structureKept: false, chrF: 0)
        #expect(EvalReport.translationMisses(model: "m", testCase: theCase, score: failed) == ["m  t: failed (other)"])
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter "EvalRunTests|EvalReportTests"`
Expected: FAIL to compile, "cannot find 'EvalRun' in scope".

- [ ] **Step 3: Write `EvalRun.swift`**

```swift
import Foundation

/// One case, one model, one repetition, as saved.
public struct CaseRecord: Sendable, Equatable, Codable {
    public let model: String
    public let caseID: String
    public let run: Int
    public let seconds: Double
    /// The corrected or translated text. Golden-set text is synthetic, so
    /// saving it is safe (NFR-P8); results are git-ignored all the same.
    public let output: String?
    public let failureDetail: String?
    public let correction: CorrectionScore?
    public let translation: TranslationScore?

    public init(
        model: String, caseID: String, run: Int, seconds: Double, output: String?,
        failureDetail: String?, correction: CorrectionScore?, translation: TranslationScore?
    ) {
        self.model = model
        self.caseID = caseID
        self.run = run
        self.seconds = seconds
        self.output = output
        self.failureDetail = failureDetail
        self.correction = correction
        self.translation = translation
    }
}

/// A whole run, saved to `evals/results/` and read back by `--compare`.
public struct EvalRun: Sendable, Equatable, Codable {
    public let startedAt: Date
    public let commit: String
    public let correction: [CorrectionSummary]
    public let translation: [TranslationSummary]
    public let records: [CaseRecord]

    public init(
        startedAt: Date, commit: String, correction: [CorrectionSummary],
        translation: [TranslationSummary], records: [CaseRecord]
    ) {
        self.startedAt = startedAt
        self.commit = commit
        self.correction = correction
        self.translation = translation
        self.records = records
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> EvalRun {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EvalRun.self, from: data)
    }

    /// `yyyy-MM-dd-HHmm-<commit>.json`.
    public static func fileName(startedAt: Date, commit: String, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "\(formatter.string(from: startedAt))-\(commit).json"
    }
}
```

An `.iso8601` date loses sub-second precision. That's why `roundTrip` uses a whole-second date; keep it that way.

- [ ] **Step 4: Write `EvalReport.swift`**

```swift
import Foundation

/// The evaluation report as text: the comparison table and the misses.
public enum EvalReport {

    public static func table<S: EvalSummary>(_ title: String, _ summaries: [S], baseline: [S]) -> String {
        guard let first = summaries.first else { return "" }
        var rows = [["metric"] + summaries.map(\.model)]
        for metric in first.metrics {
            var row = [metric.name]
            for summary in summaries {
                row.append(cell(metric.name, of: summary, baseline: baseline))
            }
            rows.append(row)
        }
        return ([title] + render(rows)).joined(separator: "\n")
    }

    private static func cell<S: EvalSummary>(_ name: String, of summary: S, baseline: [S]) -> String {
        guard let metric = summary.metrics.first(where: { $0.name == name }) else { return "" }
        let value = format(metric.value, metric.kind)
        guard let earlier = baseline.first(where: { $0.model == summary.model }),
              let delta = summary.delta(from: earlier).first(where: { $0.name == name })
        else { return value }
        return "\(value) (\(signedChange(delta.change, delta.kind)))"
    }

    private static func render(_ rows: [[String]]) -> [String] {
        let columns = rows.map(\.count).max() ?? 0
        let widths = (0..<columns).map { column in
            rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0
        }
        return rows.map { row in
            row.enumerated()
                .map { $1.padding(toLength: widths[$0], withPad: " ", startingAt: 0) }
                .joined(separator: "  ")
                .replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        }
    }

    public static func format(_ value: Double, _ kind: MetricKind) -> String {
        switch kind {
        case .rate: return String(format: "%.1f%%", value * 100)
        case .count: return String(Int(value.rounded()))
        case .seconds: return String(format: "%.1fs", value)
        case .score: return String(format: "%.1f", value)
        }
    }

    public static func signedChange(_ change: Double, _ kind: MetricKind) -> String {
        switch kind {
        case .rate: return String(format: "%+.1fpp", change * 100)
        case .count:
            let whole = Int(change.rounded())
            return whole < 0 ? String(whole) : "+\(whole)"
        case .seconds: return String(format: "%+.1fs", change)
        case .score: return String(format: "%+.1f", change)
        }
    }

    public static func correctionMisses(
        model: String, testCase: CorrectionCase, score: CorrectionScore
    ) -> [String] {
        let prefix = "\(model)  \(testCase.id): "
        if let failure = score.failure { return [prefix + "failed (\(failure.rawValue))"] }
        var lines = score.missedFixes.map { wrong in
            let expected = testCase.fixes.first { $0.wrong == wrong }?.right.first ?? ""
            return prefix + "missed \"\(wrong)\" (expected \"\(expected)\")"
        }
        lines += score.guardViolations.map { prefix + "must not contain \"\($0)\"" }
        if score.cleanPassed == false { lines.append(prefix + "the clean text was changed or flagged") }
        return lines
    }

    public static func translationMisses(
        model: String, testCase: TranslationCase, score: TranslationScore
    ) -> [String] {
        let prefix = "\(model)  \(testCase.id): "
        if let failure = score.failure { return [prefix + "failed (\(failure.rawValue))"] }
        var lines: [String] = []
        if score.esszettAbsent == false { lines.append(prefix + "contains an eszett") }
        lines += score.missingTerms.map { prefix + "term \"\($0)\" not kept" }
        if score.sentinelDebris { lines.append(prefix + "a placeholder was left in the output") }
        if !score.structureKept { lines.append(prefix + "structure changed") }
        return lines
    }
}
```

`String(format: "%.1f", 6.25)` gives `"6.2"` (round half to even on the binary value). If the formatting row for `6.25` shows `6.3` on either toolchain, change the test value to `6.24`; don't change the code.

- [ ] **Step 5: Run them to verify they pass**

Run: `swift test --filter "EvalRunTests|EvalReportTests"`
Expected: PASS.

- [ ] **Step 6: Plant a defect and watch it fail**

In `cell`, drop the `$0.model == summary.model` condition (use `baseline.first`). Expected: `baseline` fails, because gamma gains a change. Revert.

- [ ] **Step 7: Add both files to the mutation list**

Before the `WordDiff.swift"` line:

```
          Sources/BabelOtterKit/Eval/EvalReport.swift
          Sources/BabelOtterKit/Eval/EvalRun.swift
```

- [ ] **Step 8: Run the whole suite and commit**

Run: `swift test`
Expected: PASS.

```bash
git add Sources/BabelOtterKit/Eval/EvalRun.swift Sources/BabelOtterKit/Eval/EvalReport.swift \
  Tests/BabelOtterKitTests/Eval/EvalRunTests.swift Tests/BabelOtterKitTests/Eval/EvalReportTests.swift \
  .github/workflows/mutation.yml
git commit -m "feat(eval): the saved run, the comparison table and the misses

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: The golden set (the user reviews it before commit)

**Files:**
- Create: `evals/golden/correction.json`
- Create: `evals/golden/translation.json`
- Test: `Tests/BabelOtterKitTests/Eval/GoldenFilesTests.swift`

**Interfaces:**
- Consumes: `GoldenSet.load` (Task 2), `ErrorCategory`, `SourceTree.repositoryRoot` (existing test support).

**Content rules, all mandatory:**

- **Synthetic.** Invented people only: Frau Muster, Herr Beispiel, Lea, Jonas, Nina. Invented places and organisations: Otterbach, Riverside, the Weidenhof school. No real names, institutions, addresses, email addresses, phone numbers or account numbers. Rewrite any real learner text you take inspiration from, so that nothing personal or institutional remains.
- **Correction:**
  - At least 25 cases, aiming for 30.
  - Every `ErrorCategory` covered by at least two fixes: `case`, `word order`, `gender`, `agreement`, `false friend`, `spelling`, `register`, `preposition`, `other`.
  - At least 5 clean cases (`"clean": true`, `"fixes": []`) in natural Swiss Standard German with no eszett.
  - At least 2 multi-paragraph learner texts (paragraphs separated by `\n\n`) with several errors each.
  - At least 1 case with a do-not-translate term inside the text (`"terms": ["Otterbach"]`).
  - At least 1 Swiss eszett case: the text contains `ß`, and a fix expects `ss`.
  - At least 1 register case using `"profile": "administration"` (Sie): the text addresses the reader as du, and the fix expects Sie.
  - At least 1 meaning-guard case with `mustNot`: "mit der Kollege" -> must not become "Kollegin".
  - The four misses from the 2026-10-01 handoff, rewritten as new sentences: a lowercase "ich" starting a sentence, "eine Sätze", "in Deutsch" (should be "auf Deutsch"), and "probiere ... um ... zu".
- **Fix authoring:**
  - Make `wrong` long enough to be unique in its text: two or three words, not a lone "der".
  - List every acceptable `right` alternative.
  - Never put `wrong` inside a `right` alternative.
- **Translation:**
  - At least 18 cases, aiming for 20.
  - At least 7 in each direction (`en-de-ch`, `de-ch-en`).
  - At least 2 bullet lists using `- ` markers.
  - At least 2 multi-paragraph texts.
  - At least 3 cases with protected `terms`, which must appear verbatim in both `text` and `reference`.
  - At least 3 `en-de-ch` cases whose natural German has an eszett ("street", "large", "outside"), with the Swiss `ss` spelling in the `reference`.
  - Registers mixed: some cases use `"profile": "students"` or `"administration"`.
  - Every `reference` is a natural translation in Swiss Standard German (no eszett) or English.

Example entries, to copy the shape from:

```json
[
  {
    "id": "learner-jetz",
    "text": "Ich habe heute viel gemacht, und bin ich jetz sehr müde.",
    "fixes": [
      { "wrong": "jetz", "right": ["jetzt"], "category": "spelling" },
      { "wrong": "und bin ich", "right": ["und bin", "und ich bin"], "category": "word order" }
    ]
  },
  {
    "id": "guard-kollege",
    "text": "Ich habe gestern mit der Kollege gesprochen.",
    "fixes": [ { "wrong": "der Kollege", "right": ["dem Kollegen"], "category": "case" } ],
    "mustNot": ["Kollegin"]
  },
  {
    "id": "clean-sitzung",
    "text": "Die Sitzung beginnt morgen um neun Uhr im grossen Raum.",
    "fixes": [],
    "clean": true
  }
]
```

```json
[
  {
    "id": "en-de-street",
    "text": "The office in Otterbach is on a large street outside the old town.",
    "direction": "en-de-ch",
    "terms": ["Otterbach"],
    "reference": "Das Büro in Otterbach liegt an einer grossen Strasse ausserhalb der Altstadt."
  }
]
```

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing

@testable import BabelOtterKit

/// The real golden files must load, and must cover what the spec asks of
/// them (spec 2026-09-30, section 3). The content guard scans them too:
/// `evals` is one of `FixtureContentGuardTests.scannedDirectories`.
@Suite("Eval: the golden files are valid and cover the spec")
struct GoldenFilesTests {

    private static func golden() throws -> GoldenSet {
        let directory = SourceTree.repositoryRoot.appending(path: "evals/golden")
        return try GoldenSet.load(
            correction: Data(contentsOf: directory.appending(path: "correction.json")),
            translation: Data(contentsOf: directory.appending(path: "translation.json")))
    }

    @Test("both files load and validate")
    func valid() throws {
        _ = try Self.golden()
    }

    @Test("correction covers every category twice, clean texts and the special cases")
    func correctionCoverage() throws {
        let cases = try Self.golden().correction
        #expect(cases.count >= 25)
        let fixes = cases.flatMap(\.fixes)
        for category in ErrorCategory.allCases {
            #expect(fixes.filter { $0.category == category }.count >= 2, "\(category.rawValue)")
        }
        #expect(cases.filter(\.clean).count >= 5)
        #expect(cases.filter { $0.text.contains("\n\n") }.count >= 2)
        #expect(cases.contains { !$0.terms.isEmpty })
        #expect(cases.contains { $0.text.contains("\u{00DF}") })
        #expect(cases.contains { $0.profileID == "administration" })
        #expect(cases.contains { !$0.mustNot.isEmpty })
        #expect(!cases.filter(\.clean).contains { $0.text.contains("\u{00DF}") })
    }

    @Test("translation covers both directions, lists, paragraphs, terms and eszett targets")
    func translationCoverage() throws {
        let cases = try Self.golden().translation
        #expect(cases.count >= 18)
        #expect(cases.filter { $0.direction == .englishToSwissGerman }.count >= 7)
        #expect(cases.filter { $0.direction == .swissGermanToEnglish }.count >= 7)
        #expect(cases.filter { $0.text.contains("\n- ") || $0.text.hasPrefix("- ") }.count >= 2)
        #expect(cases.filter { $0.text.contains("\n\n") }.count >= 2)
        #expect(cases.filter { !$0.terms.isEmpty }.count >= 3)
        #expect(cases.contains { $0.profileID != "colleagues" })
        #expect(!cases.contains { $0.direction.targetIsGerman && $0.reference.contains("\u{00DF}") })
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter GoldenFilesTests`
Expected: FAIL, with a file-not-found error from `Data(contentsOf:)`.

- [ ] **Step 3: Draft both files**

Write `evals/golden/correction.json` and `evals/golden/translation.json` to the content rules above. Then run `swift test --filter GoldenFilesTests` and fix any validation or coverage failure it reports. The messages name the case and field.

- [ ] **Step 4: Run the content guard and the whole suite**

Run: `swift test`
Expected: PASS, `FixtureContentGuardTests` included.

- [ ] **Step 5: STOP. The user reviews both files**

Don't commit. Hand both files to the user and ask them to check every case for three things:
1. it is synthetic, with nothing real;
2. the German is right, in the texts and in every `right` alternative and `reference`;
3. the expected fixes are what a teacher would accept.

Apply their changes, re-run Step 4, and continue only when they approve.

- [ ] **Step 6: Commit**

```bash
git add evals/golden/correction.json evals/golden/translation.json Tests/BabelOtterKitTests/Eval/GoldenFilesTests.swift
git commit -m "feat(eval): the golden set, reviewed

All cases synthetic (NFR-P8); reviewed by the user before commit.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: The runner, and one real run

**Files:**
- Replace: `Sources/babelotter-eval/main.swift`
- Modify: `.gitignore`

**Interfaces:**
- Consumes:
  - `EvalArguments.parse`, `.cases(from:)`; `GoldenSet.load`;
  - `CorrectionScorer.score`, `TranslationScorer.score`, `EvalFailure.init(_:)`;
  - `CorrectionSummary.init`, `TranslationSummary.init`;
  - `EvalReport.table`, `.correctionMisses`, `.translationMisses`;
  - `EvalRun`, `CaseRecord`, `EvalRun.fileName`;
  - `OllamaClient.loopback(timeout:)`, `.installedModels()`;
  - `Corrector`, `Translator`, `Configuration.default`, `UserText`.

The runner prints synthetic golden-set text and model output. That is the one place in this repository that prints text, and it is allowed only because nothing it handles came from a user. It never reads anything but `evals/golden/` and an explicit `--compare` file.

- [ ] **Step 1: Ignore results**

Add to `.gitignore`, under the privacy block's `evals/**/*.private.*` line:

```
evals/results/
```

- [ ] **Step 2: Write the runner**

Replace `Sources/babelotter-eval/main.swift` with:

```swift
import BabelOtterKit
import Foundation

// The evaluation harness (spec 2026-09-30). Every decision lives in the kit;
// this file reads the golden set, calls the real pipelines, times them,
// prints and saves. It never runs in CI: CI has no Ollama.
//
// It prints golden-set text and model output. That is allowed here and
// nowhere else, because the golden set is synthetic (NFR-P8).

let usage = """
    usage: swift run babelotter-eval [--models a,b] [--only correct|translate|<case-id>,...]
                                     [--repeat N] [--compare evals/results/<file>.json]
    """

/// Generous, because it is an idle timeout: the transport fails a request
/// only after this long with no data at all.
let idleTimeoutSeconds: TimeInterval = 180

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func contents(_ path: String) -> Data {
    guard let data = FileManager.default.contents(atPath: path) else {
        fail("Could not read \(path). Run babelotter-eval from the repository root.")
    }
    return data
}

func seconds(since start: ContinuousClock.Instant) -> Double {
    let parts = (ContinuousClock.now - start).components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
}

func git(_ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/git")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

struct Attempt<Outcome: Sendable>: Sendable {
    let outcome: Outcome
    let output: String?
    let detail: String?
    let seconds: Double
}

func correct(_ testCase: CorrectionCase, model: String, client: OllamaClient) async -> Attempt<CorrectionOutcome> {
    var configuration = Configuration.default
    configuration.models[.correct] = model
    configuration.doNotTranslate = testCase.terms
    let corrector = Corrector(configuration: configuration, chat: client)
    let profile = configuration.profile(id: testCase.profileID) ?? .colleagues
    let start = ContinuousClock.now
    do {
        for try await event in corrector.correct(UserText(testCase.text), profile: profile) {
            if case .finished(let result) = event {
                return Attempt(
                    outcome: .corrected(result), output: result.corrected.value, detail: nil,
                    seconds: seconds(since: start))
            }
        }
        return Attempt(
            outcome: .failed(.other), output: nil, detail: "the stream ended without a result",
            seconds: seconds(since: start))
    } catch {
        return Attempt(
            outcome: .failed(EvalFailure(error)), output: nil, detail: String(describing: error),
            seconds: seconds(since: start))
    }
}

func translate(_ testCase: TranslationCase, model: String, client: OllamaClient) async -> Attempt<TranslationOutcome> {
    var configuration = Configuration.default
    configuration.models[.translate] = model
    configuration.doNotTranslate = testCase.terms
    let translator = Translator(configuration: configuration, chat: client)
    let profile = configuration.profile(id: testCase.profileID) ?? .colleagues
    let start = ContinuousClock.now
    do {
        for try await event in translator.translate(
            UserText(testCase.text), direction: testCase.direction.direction, profile: profile)
        {
            if case .finished(let result) = event {
                return Attempt(
                    outcome: .translated(result.text.value), output: result.text.value, detail: nil,
                    seconds: seconds(since: start))
            }
        }
        return Attempt(
            outcome: .failed(.other), output: nil, detail: "the stream ended without a result",
            seconds: seconds(since: start))
    } catch {
        return Attempt(
            outcome: .failed(EvalFailure(error)), output: nil, detail: String(describing: error),
            seconds: seconds(since: start))
    }
}

func progress(_ model: String, _ caseID: String, _ seconds: Double, passed: Bool) -> String {
    let id = caseID.padding(toLength: max(caseID.count, 28), withPad: " ", startingAt: 0)
    let verdict = passed ? "pass" : "miss"
    return "\(model)  \(id)  \(String(format: "%6.1f", seconds))s  \(verdict)"
}

// MARK: - Setup

let arguments: EvalArguments
do {
    arguments = try EvalArguments.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    fail("\(error)\n\n\(usage)")
}

let golden: GoldenSet
do {
    golden = try GoldenSet.load(
        correction: contents("evals/golden/correction.json"),
        translation: contents("evals/golden/translation.json"))
} catch {
    fail("The golden set is invalid: \(error)")
}

let selected: (correction: [CorrectionCase], translation: [TranslationCase])
do {
    selected = try arguments.cases(from: golden)
} catch {
    fail("\(error)")
}

var baseline: EvalRun?
if let path = arguments.compare {
    do {
        baseline = try EvalRun.decode(contents(path))
    } catch {
        fail("Could not read \(path) as an earlier run: \(error)")
    }
}

let client = OllamaClient.loopback(timeout: idleTimeoutSeconds)
let installed: [String]
do {
    installed = try await client.installedModels().map(\.name)
} catch {
    fail("Ollama could not be reached on 127.0.0.1:11434. Start it with `ollama serve` and try again.")
}

var notes: [String] = []
let models: [String]
if let requested = arguments.models {
    models = requested.filter { installed.contains($0) }
    notes += requested.filter { !installed.contains($0) }.map { "\($0): not installed, skipped" }
} else {
    models = installed
}
if models.isEmpty {
    fail("No model to run. Installed: \(installed.isEmpty ? "none" : installed.joined(separator: ", "))")
}

let commit = (git(["rev-parse", "--short", "HEAD"]) ?? "unknown")
    + ((git(["status", "--porcelain"]) ?? "").isEmpty ? "" : "-dirty")
let startedAt = Date()

// MARK: - Run

var records: [CaseRecord] = []
var correctionSummaries: [CorrectionSummary] = []
var translationSummaries: [TranslationSummary] = []
var misses: [String] = []

for model in models {
    if !selected.correction.isEmpty {
        var scores: [CorrectionScore] = []
        var times: [Double] = []
        for run in 1...arguments.repeatCount {
            for testCase in selected.correction {
                let attempt = await correct(testCase, model: model, client: client)
                let score = CorrectionScorer.score(testCase, outcome: attempt.outcome)
                let missed = EvalReport.correctionMisses(model: model, testCase: testCase, score: score)
                print(progress(model, testCase.id, attempt.seconds, passed: missed.isEmpty))
                misses += missed
                scores.append(score)
                times.append(attempt.seconds)
                records.append(CaseRecord(
                    model: model, caseID: testCase.id, run: run, seconds: attempt.seconds,
                    output: attempt.output, failureDetail: attempt.detail, correction: score,
                    translation: nil))
            }
        }
        correctionSummaries.append(CorrectionSummary(model: model, scores: scores, seconds: times))
    }
    if !selected.translation.isEmpty {
        var scores: [TranslationScore] = []
        var times: [Double] = []
        for run in 1...arguments.repeatCount {
            for testCase in selected.translation {
                let attempt = await translate(testCase, model: model, client: client)
                let score = TranslationScorer.score(testCase, outcome: attempt.outcome)
                let missed = EvalReport.translationMisses(model: model, testCase: testCase, score: score)
                print(progress(model, testCase.id, attempt.seconds, passed: missed.isEmpty))
                misses += missed
                scores.append(score)
                times.append(attempt.seconds)
                records.append(CaseRecord(
                    model: model, caseID: testCase.id, run: run, seconds: attempt.seconds,
                    output: attempt.output, failureDetail: attempt.detail, correction: nil,
                    translation: score))
            }
        }
        translationSummaries.append(TranslationSummary(model: model, scores: scores, seconds: times))
    }
}

// MARK: - Report

print("")
for note in notes { print(note) }
if !correctionSummaries.isEmpty {
    print(EvalReport.table("Correction", correctionSummaries, baseline: baseline?.correction ?? []))
    print("")
}
if !translationSummaries.isEmpty {
    print(EvalReport.table("Translation", translationSummaries, baseline: baseline?.translation ?? []))
    print("")
}
if !misses.isEmpty {
    print("Misses")
    for line in misses { print("  " + line) }
    print("")
}

let run = EvalRun(
    startedAt: startedAt, commit: commit, correction: correctionSummaries,
    translation: translationSummaries, records: records)
let directory = "evals/results"
do {
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let path = directory + "/" + EvalRun.fileName(startedAt: startedAt, commit: commit)
    try run.encoded().write(to: URL(filePath: path))
    print("Saved \(path)")
} catch {
    fail("Could not save the results: \(error)")
}
```

Each case's own `do`/`catch` inside `correct` and `translate` is what keeps one failed case from ending the run (Review Focus 4).

- [ ] **Step 3: Build with warnings as errors, and run the guards**

Run: `swift build --product babelotter-eval -Xswiftc -warnings-as-errors`
Expected: Build complete. If strict concurrency flags a top-level variable used inside `correct`/`translate`, check that both take `client` as a parameter (they do) and that nothing else from the top level is captured.

Run: `swift test`
Expected: PASS. `NetworkingCallSiteTests` passes because `main.swift` contains none of its symbols. Check by eye that the comments don't mention any of them either.

- [ ] **Step 4: Check the argument errors**

Run: `swift run babelotter-eval --repeat 0; echo "exit $?"`
Expected: `--repeat needs a whole number of at least 1, not 0`, the usage text, then `exit 1`.

Run: `swift run babelotter-eval --only no-such-case; echo "exit $?"`
Expected: `no case named no-such-case`, then `exit 1`.

- [ ] **Step 5: Check the unreachable-Ollama message**

Quit Ollama (menu bar, or `pkill -x ollama` if the user agrees), then run `swift run babelotter-eval --only correct; echo "exit $?"`.
Expected: `Ollama could not be reached on 127.0.0.1:11434...`, then `exit 1`. Restart Ollama afterwards. If quitting Ollama isn't acceptable to the user at this point, skip this step and record that it was skipped.

- [ ] **Step 6: One real run**

Run: `swift run -c release babelotter-eval --models mistral-small3.2:24b`
Expected: one progress line per case, the two tables, the misses, and `Saved evals/results/<...>.json`. Expect about 50 cases at 5-20 s each, so roughly 5-15 minutes.

Then run `swift run -c release babelotter-eval --models mistral-small3.2:24b --only correct --compare evals/results/<the file just saved>.json`.
Expected: the correction table with a change in brackets on every cell.

Record both outputs (tables plus misses) for the PR description in Task 11. Don't commit the results file: `git status` must not list it.

- [ ] **Step 7: Commit**

```bash
git add Sources/babelotter-eval/main.swift .gitignore
git commit -m "feat(eval): babelotter-eval runs the golden set on local models

Thin runner: every decision is in the kit. Results go to the
git-ignored evals/results/.

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Handoff and pull request

**Files:**
- Modify: `docs/HANDOFF.md`

- [ ] **Step 1: Update the handoff**

At the top of `docs/HANDOFF.md`, under the title, add a section `## Update <date>: the evaluation harness is built` covering:
- how to run it: `swift run -c release babelotter-eval [--models ...] [--only ...] [--repeat N] [--compare ...]`, from the repository root, with Ollama running;
- the first real run's numbers for the default model (both tables) and its most telling misses;
- where results go (`evals/results/`, git-ignored) and how to compare;
- that the golden set was reviewed by the user, and the rules for adding a case (Task 9's content rules, in short);
- the next step: change a prompt, re-run with `--compare`, and keep the change only if recall rises without over-correction or guard violations rising.

Update the title date.

- [ ] **Step 2: Run everything one last time**

Run: `swift test && swift build --product BabelOtterApp -Xswiftc -warnings-as-errors && swift build --product babelotter-eval -Xswiftc -warnings-as-errors`
Expected: all pass.

- [ ] **Step 3: Commit, push, and open the PR**

```bash
git add docs/HANDOFF.md
git commit -m "docs: handoff after the evaluation harness

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git push
gh pr create --base main --title "Evaluation harness: golden set, scorers and babelotter-eval" --body "<summary, the first run's tables, Closes #74, Closes #75, Closes #76>"
```

The PR body ends with the line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

- [ ] **Step 4: Wait for CI, mutation included**

Run: `gh pr checks --watch`
Expected: Build and test pass, and the mutation job passes at 80% or more. For any reported survivor in `Eval/`, plant it by hand first (Global Constraints) before writing a test for it.
