# Re-pitch text at a different audience — design

**Status:** approved in conversation 2026-10-16, pending review of this document.
**Milestone:** M3 Explain, Re-pitch & Polish. **Covers:** #66 (epic #10): select a text, pick the audience it should now address, and get the same text in the same language with the register and tone re-aimed and the facts kept.
**Parent spec:** `docs/superpowers/specs/2026-09-18-babelotter-design.md`, section 4.5 (`FR-RPT-01`) and section 4.6 (audience profiles).

## 1. What it does

- **Same language, new audience.** Re-pitch works on any enabled language (English and Swiss Standard German today). The text stays in its own language; form of address (du/Sie), register and tone change to suit the chosen audience. Paragraphs and lists keep their layout. Swiss German output never contains `ß`.
- **The audience is chosen, never guessed.** The popup opens with the audience picker set to the audience last re-pitched to in this application (then anywhere, then Colleagues) and a **Re-pitch** button as the default. Return starts it; picking another audience in the picker starts with that one. Nothing reaches the model before an audience is confirmed.
- **Facts are kept, and checked.** The prompt asks for every fact to be kept. A local check then lists any number, date, time, web address or email address from the original that is missing from the result, as a warning above the actions. Replace stays available.
- **Like Translate once running.** The result streams in; Replace (default), Copy and Regenerate are available; another audience or a style note re-runs. The header reads "Re-pitch · English" (the detected language); there is no Swap.
- **A hotkey and a menu entry.** Control-Option-R by default, configurable as `"repitch"` in `config.json` or `null` for the menu only. The menu lists "Re-pitch Selection (Control-Option-R)".
- **Unknown language.** When detection cannot tell, the popup asks "Which language is this?" with one button per enabled language. A language that is not enabled is reported: "This looks like fr, which is not one of your languages."

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| Which languages | Any enabled language, kept as it is | Re-aiming an English email from colleagues to students is as useful as a German one; languages are configuration (`FR-LNG-01`); detection keeps the language rather than translating, so it costs almost nothing |
| How the audience is chosen | Last re-pitch audience pre-selected; Return or a pick starts | The story asks for an explicit choice; one key for the common case, and never a paste in a register the user did not confirm |
| What is remembered | Re-pitch's own last target audience per application, separate from Translate's | Translate remembers whom texts in that app address; Re-pitch remembers whom the user re-aims at. Mixing them would make each the other's wrong default |
| How it is built | `Translator` gains a Re-pitch entry point: the same pipeline with the source equal to the target and a fixed audience | Re-pitch is a same-language translation for a fixed audience: blocks, the single retry, degrade to raw text, preview, DNT and locale rules are all already there and tested. A separate pipeline would copy about 250 lines of the trickiest code |
| Glossary | Not applied; the audience's preferred terms are | Glossary entries are pairs for translating between two languages |
| Reply shape | `{"blocks": ["..."]}` only | `detected_source` and `detected_audience` have no meaning when both are known |
| Fact preservation | Prompt instruction plus a local check that warns | A wrong date or a lost link is the most damaging drift; a deterministic check costs no extra model call. A warning, not a block: the user decides |

## 3. The prompt

Instruction:

> You are an editor. Rewrite the blocks below for the audience described, in the same language. Change the form of address, the register and the tone to suit that audience. Keep every fact: names, dates, times, numbers, places, links and requests. Do not add or remove information. Do not translate.

Then, as for the other actions: `Language: <display name>.`; the orthography section of that language's locale rules (for Swiss Standard German: never `ß`, always `ss`); the fixed audience section (`Audience:`, `Address the reader as`, `Tone:`, preferred terms); the protected-terms section when DNT terms exist; the style note; the schema `{"blocks": ["..."]}`; the blocks with their count, as a JSON array (numbered before #103's round 3, until Gemma 4 copied the numbers into its reply).

## 4. The kit

### 4.1 `Translator`

- `public func language(for text: UserText) -> Result<LanguageCode, TranslationError>`: the text's enabled language. A confident detection matching an enabled language (outright or by base subtag, as `TargetLanguageResolver` matches) gives that language, however many others are enabled; a confident detection of a language not enabled gives `.languageNotConfigured(code)`; any ambiguous detection gives `.directionUnknown(candidates:)` with the enabled languages. Not `TargetLanguageResolver` itself: it reports "ambiguous" when there is more than one language to translate into, which Re-pitch does not need.
- `public func repitch(_ text: UserText, language: LanguageCode, audience: AudienceProfile, styleNote: String? = nil) -> LazyStream<TranslationEvent>`: the existing pipeline with `Direction(source: language, target: language)`, `.fixed(audience)`, and `action: .repitch`.
- `Context` gains `action: Action`. It decides the prompt's action, the model (`configuration.models[action] ?? Configuration.defaultModel`) and the glossary (none for `.repitch`).
- The result's `warnings` gain the fact check's (4.3) for `.repitch` only, after the existing ones.
- `translate(...)` is unchanged in behaviour and signature.

### 4.2 `PromptBuilder` and the reply

- The `.repitch` instruction becomes the text in section 3.
- The `.repitch` schema becomes `{"blocks": ["..."]}`.
- `ResponseParser.parseTranslate` already decodes a reply with `blocks` only: `TranslateResponse`'s other fields are optional (checked 2026-10-16).

### 4.3 `FactCheck` (`Sources/BabelOtterKit/Text/FactCheck.swift`)

`public enum FactCheck { public static func missing(from original: String, in result: String) -> [String] }`

- Facts are: numbers (digit runs, joined by `.`, `,`, `:`, `/` or `-` between digits, so `12.11.2026`, `14:30`, `3,5` and `2026-11-12` are one fact each); web addresses (`http://`, `https://` or `www.` up to the next space, trailing `.,;:!?)` trimmed); email addresses (`local@domain.tld`).
- A fact counts as kept when it occurs anywhere in the result as written. Each missing fact is reported once, in order of first appearance.
- The result's warning per missing fact: `"<fact>" from the original is not in the re-pitch.`
- Pure string scanning, no regex literals needed; ASCII source.

### 4.4 `AudienceSession`

- `.repitch` behaves like `.correct`: `isDetecting` is false, `request` is `.fixed(audience)`, start order is this app's last choice, the last choice anywhere, Colleagues.
- Re-pitch uses its own `AudienceMemory` instance (4.6), so its start reads and its picks write only Re-pitch's choices.

### 4.5 Hotkeys and readiness

- `HotKeyBindings.repitch`, default text `control+option+R`, decoded and encoded under `repitch`; `null` turns it off.
- `HotKeyPlan.actions` becomes `[.translate, .correct, .explain, .repitch]`; `launchCombinations[.repitch]` is key code 0x0F (kVK_ANSI_R), modifiers 0x1800, "Control-Option-R".
- The readiness check covers Re-pitch's model.

### 4.6 Mutation gate

`Sources/BabelOtterKit/Text/FactCheck.swift` joins the PASS1 list. The kit's constraints apply: ASCII only, no comma-joined conditions in `if`/`guard`/`while`, no ternary over an enum.

## 5. The app

### 5.1 Memory

`UserDefaultsAudienceMemory` gains a key prefix (`init(prefix: String = "")`). Translate and Correct keep today's keys (empty prefix); Re-pitch uses `"repitch."`, so no existing choice moves.

### 5.2 `PopupModel`

- `usesDirection` is false for `.repitch` (only Translate runs in a direction).
- `begin(with:)` for `.repitch`: `translator.language(for:)`; success sets `language` and phase `.choosingAudience`; `.directionUnknown(candidates)` sets `.choosingDirection(candidates)`, whose buttons call `choose(target:)`, which for Re-pitch sets the language and moves to `.choosingAudience`; `.languageNotConfigured(code)` fails with "This looks like <code>, which is not one of your languages."
- `startRepitch()` (the Re-pitch button and Return) runs with the shown audience. `selectProfile(_:)` during `.choosingAudience` records the pick and starts; after that it re-runs, as for Translate.
- The run consumes `translator.repitch(...)` with the existing `apply(_ event: TranslationEvent)`; Replace, Copy and Regenerate as for Translate (`canReplace` true when finished).
- `canRegenerate` for Re-pitch needs a language; it is false during `.choosingAudience` (the Re-pitch button is the start).

### 5.3 `PopupView`

- Header: "Re-pitch · <language display name>" once the language is known, "Re-pitch" before; no Swap.
- `.choosingAudience`: the controls row (picker with note, style note) and a **Re-pitch** button with the default action (Return), while the style note field does not have focus; Return in the style note field also starts.
- The style note placeholder for Re-pitch is "Style note, e.g. shorter, warmer"; Regenerate's help "Re-pitch again with this audience and instruction".
- The "Which language is this?" prompt replaces "Translate into:" in `.choosingDirection` for Re-pitch.

### 5.4 Menu

A fourth item, "Re-pitch Selection", with its current hotkey in the title, calling `startAction(.repitch)`. The Carbon hotkey id 4 is already mapped to `.repitch`.

## 6. Testing

### 6.1 Unit

- `TranslatorTests`: `language(for:)` for an enabled, a disabled and an undecided detection; `repitch` sends the Re-pitch instruction, `Language: <name>`, the fixed audience, no glossary but the audience's preferred terms, the `blocks`-only schema, to the Re-pitch model; layout survives; de-CH output has `ss`; DNT terms restored; a `blocks`-only reply decodes; a wrong block count triggers the retry; `.audience(profile, inferred: false)` is reported; a missing date and a missing link appear in `warnings`; Translate's warnings never carry fact-check lines.
- `FactCheckTests`: each fact kind found missing; kept when present in other surroundings; reported once when repeated; trailing punctuation trimmed from URLs; nothing for fact-free text; a decimal with `,` and a date with `.` are single facts.
- `PromptBuilderTests`: the Re-pitch instruction, the `blocks`-only schema, the language line, and the orthography section for de-CH.
- `AudienceSessionTests`: Re-pitch never detects, asks for a fixed audience, starts from its memory, and a pick is remembered.
- Hotkey tests: `repitch` decodes, encodes, defaults to Control-Option-R, `null` turns it off, a clash is reported.

### 6.2 Integration (local only, `BABELOTTER_INTEGRATION=1`, default model)

`RepitchIntegrationTests`, each case three runs, at least two must pass:

1. A German du-form colleague message with a date and a time, re-pitched for Administration: the result contains "Sie", none of the words "du", "dich", "dir", "dein", contains no `ß`, and `FactCheck` reports nothing missing.
2. An English colleague note with a date and a room number, re-pitched for Students: the result is detected as English and `FactCheck` reports nothing missing.

### 6.3 Manual (in HANDOFF)

- **R1.** Control-Option-R on a German draft in Mail: the popup shows "Re-pitch · Swiss Standard German", the last audience pre-selected and a Re-pitch button; Return starts it and the result streams in.
- **R2.** Picking another audience re-runs with it; Replace pastes the result; the menu lists "Re-pitch Selection (Control-Option-R)".

## 7. Out of scope

- Re-pitching into another language (that is Translate with an audience).
- Inferring the source audience to explain what changed.
- A shared pipeline for Correct and Explain.
