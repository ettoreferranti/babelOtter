# Correct — design

**Status:** approved in conversation 2026-09-28, pending review of this document.
**Milestone:** M2 Correct & Tutor. **Covers:** #40, #62, #63, #64 (epic #9).
**Parent spec:** `docs/superpowers/specs/2026-09-18-babelotter-design.md`, section 4.3 (`FR-COR-01`..`06`).

## 1. What it does

Select German text anywhere and press **Control-Option-C**. A popup near the
cursor streams the corrected text. It then shows:

- an inline word-level diff of your text against the correction;
- every error fixed, each with a category and an English explanation of the rule;
- stylistic suggestions, listed but not applied.

**Replace** pastes your text with only the *errors* fixed. Suggestions never
reach your document unless you adopt one by hand. The first rule of
`FR-COR-01` is to correct the language and keep the author's voice, and a
suggestion is by definition a matter of taste.

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| Trigger | Its own hotkey, Control-Option-C, plus a "Correct Selection" menu item | One press; `FR-UI-01` asks for a hotkey per action |
| Languages | German only. Other text gets "Correct works on German text", and nothing is sent | The error taxonomy (`FR-COR-03`) is German-shaped. Tutoring is the goal |
| What Replace pastes | Errors fixed; suggestions listed, not applied | Keeps the author's voice by default |
| How the errors-only text is produced | The model applies only severity `error`; the kit verifies the answer against itself (approach A) | One pass. Reverting suggestions in code (B) is fragile, and two passes (C) doubles the wait at about 6.6 tokens/s |
| Explanation language | English | `FR-COR-02` |

## 3. Kit (`BabelOtterKit`) — pure, test-first, mutation-gated

### 3.1 `WordDiff` (#40) — `Sources/BabelOtterKit/Text/WordDiff.swift`

```swift
public enum DiffSegment: Sendable, Equatable {
    case same(String)
    case removed(String)
    case added(String)
}
public enum WordDiff {
    public static func diff(_ original: String, _ revised: String) -> [DiffSegment]
}
```

- **Tokens:** a run of letters and digits (Unicode-aware, so umlauts and ß stay inside words); a run of whitespace; each punctuation character on its own.
- **Algorithm:** longest common subsequence over tokens. Ties prefer showing a removal before an addition. Adjacent segments of the same kind are merged.
- **Invariants,** tested for every case:
  - Concatenating the `same` and `removed` segments gives back `original` exactly.
  - Concatenating the `same` and `added` segments gives back `revised` exactly.
- It knows nothing about correction, so Re-pitch can reuse it.

### 3.2 Prompt changes — `PromptBuilder`

- Correct's instruction gains the rule: *"`corrected_blocks` applies only changes whose severity is `error`. List stylistic suggestions in `errors` with severity `suggestion`, and do not apply them to `corrected_blocks`."*
- Correct's prompt includes the chosen audience's register ("du" or "Sie"), so `register` errors are judged against it. The existing audience section already does this; Correct must include it.
- The per-invocation style note is supported, exactly as for Translate.

### 3.3 `CorrectionCheck` — `Sources/BabelOtterKit/Pipeline/CorrectionCheck.swift`

A pure function of the original text, the corrected text and the itemised list. It returns warnings and never repairs anything.

| Rule | Warning when violated |
|---|---|
| Each `error`'s `corrected` fragment appears in the corrected text | "A listed correction is missing from the corrected text: …" |
| Each `suggestion`'s `original` fragment still appears in the corrected text | "A suggestion was applied although it should not have been: …" |
| The text changed, but no errors are listed | "The text was changed, but no errors are listed." |

It also decides the **"no errors" result** (`FR-COR-06`): the corrected text equals the original (after post-processing) *and* there are no `error` items. Suggestions alone do not make a text wrong.

### 3.4 `Corrector` — `Sources/BabelOtterKit/Pipeline/Corrector.swift`

Shaped like `Translator` (lazy stream, cancellable, same `ChatStreaming` seam):

```swift
public enum CorrectionEvent: Sendable, Equatable {
    case started
    case preview(UserText)          // corrected text so far, post-processed
    case finished(CorrectionResult)
}
public struct CorrectionResult: Sendable, Equatable {
    public let original: UserText
    public let corrected: UserText  // errors fixed only; what Replace pastes
    public let errors: [CorrectionError]       // severity .error, including kit-added ones
    public let suggestions: [CorrectionError]  // severity .suggestion
    public let diff: [DiffSegment]             // original -> corrected
    public let warnings: [String]
    public var hasNoErrors: Bool { get }
}
public enum CorrectionFailure: Error, Equatable {
    case notGerman                 // refused before anything is sent
    case unreadableReply           // parse failed; never shown as a correction
    case structureLost             // block count wrong twice
    case emptyResponse
}
public struct Corrector: Sendable {
    public init(configuration: Configuration, chat: any ChatStreaming,
                recognizer: any LanguageRecognizing = NaturalLanguageRecognizer())
    public func correct(_ text: UserText, profile: AudienceProfile,
                        styleNote: String? = nil) -> LazyStream<CorrectionEvent>
}
```

The pipeline, in order:

1. **Language gate.** `notGerman` is thrown, and nothing is sent, only when detection has a guess and that guess is *not* German. That covers a confident non-German result, or a below-floor result whose best guess isn't German (base subtag other than `de`). A confident German result passes. So does a below-floor result whose best guess is German, as does text too short to judge or with no hypothesis at all: short German fragments are common, and the model is told the text is German. The gate exists to catch "wrong language", not "can't tell".
2. **Structure and terms.** `StructureExtractor.extract`, then `TokenProtector.mask` with the do-not-translate list, as for Translate.
3. **Prompt and stream.** `PromptBuilder` with `.correct`, the configured German language, the profile and the style note. The model is `configuration.models[.correct]`. The preview reads `corrected_blocks` from the partial reply (see 3.5).
4. **Parse strictly.** `ResponseParser.parseCorrect`. A failure throws `unreadableReply`, with no degraded raw-text fallback. This asymmetry with Translate is deliberate (`FR-COR-06`).
5. **Block count.** `BlockCountPolicy`: one retry with the whole text as a single block. A second mismatch throws `structureLost`, again with no stitching.
6. **Post-process.** `PostProcessor.finish` on each block restores the terms and applies the Swiss rules. Protection problems become warnings.
7. **ß in the user's own text.** If the *original* contains `ß`, the kit appends a `spelling` error: "Swiss Standard German writes ss, never ß." The diff will show that change, and every change in the diff must be explained.
8. **Reassemble** with `StructureExtractor.reapply`. Restore any sentinels inside the error and suggestion fragments.
9. **Check** with `CorrectionCheck`, **diff** with `WordDiff(original, corrected)`, then emit `finished`.

### 3.5 Preview parser generalised

`PartialTranslateBlocks` becomes `PartialBlocks.extract(from:key:)`, and Translate passes `"blocks"`. The behaviour is unchanged, and the existing tests move with it.

## 4. App (`BabelOtterApp`) — checked by use

- **Hotkey and menu.** A second `HotKey` (id 2, Control-Option-C) and a "Correct Selection (Control-Option-C)" menu item. Both go through the same `translateSelection`-style entry point, parameterised by the action. The `isCapturing` / `isReplacing` / `isDismissed` rules apply unchanged.
- **`PopupModel` gains `action: Action`** (`.translate` or `.correct`). There is no second model or panel. Capture, the timeout watchdog, cancellation, Replace/Copy custody and `reopen` are shared.
- **Header for Correct:** "Correct", the audience picker and the instruction field with Regenerate. There is no Swap.
- **Streaming:** the corrected text grows, as a translation does.
- **Finished:**
  - **Diff:** flowing text. `removed` is struck through in red, `added` is green, `same` is plain. This is exactly what Replace pastes.
  - **Warnings,** if any, above the lists.
  - **Errors:** one row each, with a category chip, `original → corrected` and the explanation beneath.
  - **Suggestions (not applied):** the same rows, dimmed, each with a small Copy button for the suggested fragment.
  - **No errors:** "No errors found ✓", with Replace disabled.
- **Actions:** Replace pastes `corrected`. Copy (Command-Shift-C) copies `corrected`. Dismiss (Escape).
- **Size:** the popup allows a taller body for Correct, and the lists scroll.
- **Failures** map to plain messages:
  - `notGerman` → "Correct works on German text."
  - `unreadableReply` → "The model's reply couldn't be read as a correction. Try Regenerate."
  - `structureLost` → "The model lost the text's structure. Try Regenerate."
  - Transport errors → the existing Ollama message.

## 5. Errors and edge cases

| Case | Behaviour |
|---|---|
| Unreadable reply | `unreadableReply`; never raw text presented as a correction |
| Wrong block count twice | `structureLost`; Regenerate offered |
| `CorrectionCheck` warnings | Shown. Replace stays enabled: the diff is computed from the real text and shows exactly what will be pasted |
| Protected term damaged | A warning, as for Translate |
| No errors, suggestions present | "No errors found ✓"; the suggestions are still listed; Replace disabled |
| Mixed German/English text | Gated by detection. If it is confidently German, it is corrected; English words are the model's business |
| Timeout, Escape, Ollama down, source app quit | The existing shared paths, unchanged |

## 6. Testing

**Kit (TDD):**
- `WordDiff`: identical texts; a pure insertion; a pure deletion; a substitution; a word swap; punctuation-only changes; whitespace preserved; umlauts and ß inside words; empty either side; both round-trip invariants on every case.
- `CorrectionCheck`: each rule's pass and fail; the no-errors decision, including suggestions-only.
- `Corrector` with a scripted chat:
  - a clean correction;
  - no errors;
  - not German (nothing sent);
  - a too-short fragment allowed;
  - the one retry, then `structureLost`;
  - `unreadableReply`;
  - `emptyResponse`;
  - the ß addition;
  - sentinels restored inside the fragments;
  - the preview is post-processed;
  - laziness (nothing sent until iterated);
  - cancellation reaches the chat stream;
  - the configured `.correct` model is used.
- `PromptBuilder`: Correct's prompt contains the errors-only rule, the register and the style note.
- `PartialBlocks`: the existing cases under the new name, plus the `corrected_blocks` key.

**Integration (local, `BABELOTTER_INTEGRATION=1`):** "Ich habe gestern mit der Kollege gesprochen." against `mistral-small3.2:24b`. Expect at least one error of category `gender` or `case`, with no `CorrectionCheck` warnings.

**Mutation:**
- New kit files go into `PASS1` in `.github/workflows/mutation.yml`.
- Avoid the muter traps listed in `docs/HANDOFF.md`.
- Before writing a test to kill a reported survivor, plant that mutant by hand. muter drops mutants inside closures and nested loops, and then reports them as survivors.

**Manual (the user's), recorded in HANDOFF:**
- Control-Option-C in Word, Teams and Outlook on text with a deliberate mistake.
- A correct text ("No errors found").
- English text (refused).
- Replace pastes only the error fixes.
- The suggestion Copy button copies the fragment.

## 7. Out of scope

- History (M3).
- Mistake tracking and CEFR drills (M4).
- Correcting languages other than German.
- Per-change accept or reject toggles.
- Configurable hotkeys (M3).
