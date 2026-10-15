# Explain a German selection in English — design

**Status:** approved in conversation 2026-10-15, pending review of this document.
**Milestone:** M3 Explain, Re-pitch & Polish. **Covers:** #65 (epic #10): select German you do not fully follow, press a hotkey or use the menu, and read an English summary of its meaning with notes on its idioms and unusual constructions.
**Parent spec:** `docs/superpowers/specs/2026-09-18-babelotter-design.md`, section 4.4 (`FR-EXP-01`) and section 7 (the explain response contract).

## 1. What it does

- **Explain reads German and answers in English.** The popup, titled "Explain", shows a plain-English summary of what the selection means, streamed as it is written. When the reply is complete, a list of notes follows: each idiom, unusual construction or tricky phrase, quoted exactly as written, with its own English explanation.
- **Nothing to replace.** An explanation is not a substitute for the text, so the popup has no Replace button at all.
- **Copy takes everything.** Copy puts the summary and the notes on the clipboard as plain text; the popup text stays selectable for copying a part by hand.
- **A style note, no audience.** The controls row keeps the style note ("Style note, e.g. focus on grammar") and Regenerate. There is no audience picker: an explanation is written for you, not for a reader.
- **A hotkey and a menu entry.** Control-Option-E by default, configurable in `config.json` like Translate and Correct, or `null` for the menu only. The menu lists Explain with its current hotkey, and both go through the same path.
- **German only.** A selection that detection confidently places in another language is refused with "Explain works on German text." and nothing is sent. When detection is unsure, the text is sent.

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| A selection that is not German | Refused before any request, as Correct does; sent when detection is unsure | Matches the story and `FR-EXP-01` ("a German selection"). Explaining other languages can be added later without breaking anything |
| What Copy copies | The summary, a blank line, then one `- "phrase": explanation` line per note; the summary alone when there are no notes | One button for everything shown, ready to paste into a message or notes |
| How the pipeline is built | A separate `Explainer`, shaped like `Corrector` | Proven pattern, under the mutation gate. A shared generic pipeline would refactor two working, tested pipelines inside a feature story; it can be its own issue once Re-pitch (#66) shows what is really shared |
| Reply format | The existing JSON contract (`summary_en`, `notes[].phrase`, `notes[].explanation_en`) | Already specified (parent spec section 7). Plain text would make the notes fragile to read back |
| How the text is sent | As one block, not split into paragraphs | A summary has no layout to keep |
| What streams | The summary, as it is written; the notes arrive with the complete reply | The summary comes first in the reply and is what the user reads first |
| A reply that cannot be read | An error with "Try Regenerate", no automatic retry | As Correct does. A retry would double the wait for a rare failure |
| Locale rules | English rules on the summary and the explanations; the quoted German phrases are left exactly as returned | The phrases quote the user's own text; changing ß to ss there would misquote it |
| Audience | None | An explanation is addressed to the user |

## 3. The prompt

The instruction replaces today's one-liner:

> You are a language teacher. Explain the German text below in plain English for a reader who does not fully follow it. In summary_en, say what the text means as a whole. In notes, add one item for each idiom, unusual construction or tricky phrase: quote the phrase exactly as it is written in the text, and explain in English what it means and how it works. Do not add notes for plain words. If nothing is tricky, notes is [].

The schema line is unchanged: `{"summary_en": "...", "notes": [{"phrase": "...", "explanation_en": "..."}]}`. The style note is appended as for the other actions ("Additional instruction from the user: ..."). There is no audience section. Do-not-translate terms are masked as everywhere else.

## 4. The kit

### 4.1 `Explainer` (`Sources/BabelOtterKit/Pipeline/Explainer.swift`)

```swift
public enum ExplanationEvent: Sendable, Equatable {
    case started
    /// Another piece of the reply arrived. Feeds the popup's idle watchdog.
    case progress
    /// The summary so far, post-processed, terms restored. Never the result.
    case summary(String)
    case finished(ExplanationResult)
}

public struct ExplanationResult: Sendable, Equatable {
    public let summary: String
    public let notes: [ExplainNote]
    public let warnings: [String]
    /// What Copy writes.
    public var copyText: String { get }
}

public enum ExplanationFailure: Error, Equatable {
    case notGerman
    case unreadableReply
    case emptyResponse
}

public struct Explainer: Sendable {
    public init(configuration: Configuration, chat: any ChatStreaming,
                recognizer: any LanguageRecognizing = NaturalLanguageRecognizer())
    public func explain(_ text: UserText, styleNote: String? = nil) -> LazyStream<ExplanationEvent>
}
```

A run:

1. **Gate.** Empty text, or detection confident it is not German: `.notGerman`, and nothing is sent. Uncertain detection proceeds.
2. **Mask.** Do-not-translate terms are masked over the whole text with `TokenProtector`.
3. **Generate.** One streaming request with the text as one block, the model from `configuration.models[.explain]` (default `Configuration.defaultModel`). Each piece emits `.progress`; when the summary read so far has grown, `.summary` with it post-processed and unmasked.
4. **Parse.** The complete reply decodes strictly into `ExplainResponse`. Invalid JSON, or an empty summary: `.unreadableReply`. An empty reply: `.emptyResponse`.
5. **Clean.** Terms are restored in the summary, in each phrase and in each explanation. Notes whose phrase or explanation is empty after trimming are dropped. English locale rules (the post-processor for the configured English language) apply to the summary and the explanations; phrases are left as returned.
6. **Finish.** `.finished(ExplanationResult)`.

### 4.2 Reading a value still arriving

`PartialField` gains `prefix(named:in:) -> String?`: the value of a string field read so far, whether or not its closing quote has arrived. Nil while the field or its opening quote has not arrived. An escape cut off at the end is left out until it completes (`PartialBlocks.readString` already behaves this way).

### 4.3 Hotkeys and readiness

- `HotKeyBindings` gains `explain: HotKeyBinding`, decoded and encoded under the `explain` key; default text `control+option+E`; `null` turns it off.
- `HotKeyPlan.actions` becomes `[.translate, .correct, .explain]`, so a clash with Translate or Correct is reported the existing way, earlier actions winning.
- The readiness check (`ReadinessMonitor`) covers Explain as it covers Translate and Correct.
- Re-pitch stays without a hotkey until #66.

### 4.4 Mutation gate

`Sources/BabelOtterKit/Pipeline/Explainer.swift` is added to the PASS1 list in `.github/workflows/mutation.yml`. The kit's constraints apply: ASCII only, no comma-joined conditions in `if`/`guard`/`while`, no ternary over an enum.

## 5. The app

### 5.1 `PopupModel`

- Holds an `Explainer` and `private(set) var explanation: ExplanationResult?`.
- `begin(with:)` sends `.explain` to `runExplanation()`. `regenerate()` and `canRegenerate` treat Explain like Correct: they need the captured selection, not a direction. Swap is unavailable.
- Events: `.summary` sets `text`; `.finished` sets `explanation`, `text = copyText`, `warnings`, and phase `.finished`.
- `canReplace` splits in two: `canCopy` (finished and not yet copied; for Correct, only when there are errors, as today) and `canReplace` (`canCopy`, and the action is not Explain). `copy()` checks `canCopy`.
- `describeExplanation` maps failures: "Explain works on German text."; "The model's reply couldn't be read as an explanation. Try Regenerate."; "Nothing came back from the model."; anything else as `describe` does today.

### 5.2 `PopupView` and `ExplanationViews.swift`

- Header title "Explain".
- Controls row without the audience picker and its note; the style note placeholder is "Style note, e.g. focus on grammar"; Regenerate's help text "Explain again with this instruction".
- Finished content: the summary as body text; when there are notes, a divider, then one row per note: the phrase in bold, the explanation below it in secondary colour. All text selectable. A long result scrolls within a capped height, as Correct's does. No notes: no list and no empty-state message.
- The Replace button is hidden for Explain, not disabled.

### 5.3 `AppDelegate`

A third menu item, "Explain", with its current hotkey in the title like the others, calling `startAction(.explain)`. The Carbon hotkey id 3 is already mapped to `.explain`.

## 6. Testing

### 6.1 Unit (Swift Testing, fake chat stream as in `CorrectorTests`)

- `ExplainerTests`: confident non-German refused with no request; uncertain detection sent; the request carries one block, the Explain model, masked terms and the style note; a growing summary emits growing `.summary` events and notes only arrive with `.finished`; `.progress` per piece; terms restored in summary, phrases and explanations; English rules on summary and explanations, a phrase with ß left as returned; empty notes dropped; empty summary and invalid JSON are `.unreadableReply`; an empty reply is `.emptyResponse`; `copyText` with and without notes.
- `PartialFieldTests`: `prefix` reads an open value, a closed one, nothing before the opening quote, and leaves out a cut-off escape.
- `PromptBuilderTests`: the new instruction, and no audience section for Explain.
- `HotKeyBindings` and `HotKeyPlan` tests: `explain` decodes, encodes, defaults to Control-Option-E, `null` turns it off, and a clash with Translate or Correct is reported.

### 6.2 Integration (local only, `BABELOTTER_INTEGRATION=1`, default model)

`ExplainIntegrationTests`:

1. "Das ist nicht mein Bier, aber wir haben den Vertrag unter Dach und Fach gebracht." gives a non-empty English summary and at least one note whose phrase contains "Bier" or "Dach und Fach".
2. "Die Sitzung beginnt um 10 Uhr." gives a non-empty summary and a reply that parses; zero notes is not required.
3. An English sentence is refused with `.notGerman` before any request.

### 6.3 Manual (in HANDOFF)

- **E1.** Control-Option-E on a German paragraph in Mail: the popup is titled "Explain", the summary streams in, the notes appear when it finishes.
- **E2.** No Replace button; Copy pastes the summary and notes; the menu lists Explain with its hotkey and behaves as the hotkey does.

## 7. Out of scope

- Explaining languages other than German, or explaining into a language other than English.
- A shared pipeline for Correct, Explain and Re-pitch.
- Re-pitch (#66), including its hotkey.
