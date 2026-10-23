# French and Italian, and Translate with any number of languages — design

**Status:** approved in conversation 2026-10-23, pending review of this document.
**Milestone:** M4. **Covers:** the first of two PRs for #81 (epic #15): Translate and Re-pitch with three or more languages, French and Italian shipped, golden-set directions. **Not here:** Correct and Explain stay German-only (with English explanations) until the second PR, which gets its own design.

## 1. What it does

- **French (`fr`) and Italian (`it`) ship**, switched off. In Settings › General they appear as toggles under English and Swiss Standard German. Their formality words are vous/tu and Lei/tu. No orthography rules.
- **Existing installs get them too.** On load, any shipped language whose base code is missing from `config.json` is appended, switched off, and the file is written back once. A user's own `fr-CH` counts as French, so `fr` is not added beside it.
- **With exactly two languages enabled nothing changes**: one source, one target, Swap reverses them.
- **With three or more**, Translate detects the source and then:
  - uses the **target last chosen for that source**, if it is still enabled;
  - otherwise opens **"Translate into:"** with the other enabled languages; the choice is remembered for that source.
- **The header becomes a target menu** with three or more: "French → German ▾" lists the other enabled languages; choosing one re-runs with the same source and remembers it. With two it stays the Swap button.
- **When the source is not known** (detection below the floor, or too short), with three or more languages the popup asks **"Which language is this?"** first, then the target (skipped when one is remembered for that source). With two it stays as today: pick the target, the source is the other one.
- **Detection only considers enabled languages.** French and Italian are easy to confuse on a short text; limiting the recognizer to the enabled languages makes it choose among them. A text in a language that is not enabled is matched to the closest enabled one, and the confidence floor still asks when unsure. The "not one of your languages" message goes away.
- **Re-pitch** already works for any enabled language (`Translator.language(for:)`); it benefits from the constrained detection and needs nothing else.
- **The golden set** gains fr↔en and it↔en, five synthetic cases per direction (20), and directions become data.

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| Split | Two PRs; this one is Translate and Re-pitch | Correct and Explain need their own prompts and decisions; Translate is useful on its own |
| Variants | `fr` and `it`, named "French" and "Italian" | Neutral for readers outside Switzerland; a user can still write `fr-CH` in `config.json` |
| Target with 3+ | Remembered per source; picker the first time | One click once per source, none after |
| Swap with 3+ | The header becomes a target menu | "Swap" means nothing when the text is in neither language |
| Where choices are remembered | UserDefaults (`targetBySource`: source code → target code), never `config.json` | Picking a target must not rewrite a file the user may be editing; only language codes, never text |
| Existing configs | Missing shipped languages appended, disabled, written back once | They appear as toggles; nothing changes until switched on |
| Detection | Constrained to enabled languages' base codes | Accuracy among close languages; the floor still guards |
| Golden set | fr↔en and it↔en, 5 each | The user's choice; directions become data so more can be added without code |
| Glossary columns | Only enabled languages | Four columns would crowd the table; a disabled language's terms are kept untouched |

## 3. The kit (`Sources/BabelOtterKit/`)

- `LanguageConfig.french` (`fr`, "French", `AddressForms(formal: "vous", informal: "tu")`, disabled) and `.italian` (`it`, "Italian", `AddressForms(formal: "Lei", informal: "tu")`, disabled). `shippedDefaults` = English, Swiss Standard German, French, Italian. The `addressForms` fill for files without it (base-code lookup in the shipped list) now covers fr and it.
- `Configuration.addingMissingShippedLanguages() -> Configuration?`: the configuration with every shipped language whose base subtag no configured language has, appended disabled; `nil` when nothing is missing (so the app knows whether to write).
- `NaturalLanguageRecognizer(constraints: [LanguageCode])`: sets `languageConstraints` to the base subtags (`NLLanguage(rawValue:)`); empty means unconstrained. `LanguageDetector(configuration:)` builds its default recognizer constrained to the enabled languages; an injected recognizer is used as given (tests).
- `TargetLanguageResolver.resolve(_:remembered:)`, with `remembered: [LanguageCode: LanguageCode]` (default empty):
  - one other enabled language: `.resolved` as today;
  - several, and `remembered[source]` is one of them: `.resolved(source, that)`;
  - several, none remembered: `.ambiguousPairing(source: source, candidates: others)` (the source is now carried).
- `TranslationError.directionUnknown(source: LanguageCode?, candidates:)`: the source when detected, `nil` when not.
- `Translator.direction(for:remembered:)` passes the memory through. `Translator.direction(from source: LanguageCode?, into target:)` replaces `direction(into:)`: with a source, that source (must be enabled and differ from the target); without one, the other enabled language when exactly two are enabled, else `nil`.
- `TargetChoice` (`Text/TargetChoice.swift`), pure: `menuTargets(source:configuration:) -> [LanguageCode]` (the other enabled languages, in configuration order) and `usesMenu(configuration:) -> Bool` (three or more enabled). Its wording lives with the popup's other strings.
- Golden set: `TranslationDirection` becomes a struct `{ source, target }` parsed from the existing strings by matching shipped codes on either side of a `-` (`"en-de-ch"`, `"de-ch-en"`, `"en-fr"`, `"fr-en"`, `"en-it"`, `"it-en"`); an unknown code is a `GoldenSetError` naming the field. `targetIsGerman` becomes "the target has locale rules": the scorer checks that none of the target's rules' `replace` strings appear in the output (today's eszett check, generalised). The eval runner enables every shipped language in its configuration.

All of it under the mutation gate: new files join PASS1 in `.github/workflows/mutation.yml`; the gate's source rules apply (ASCII only, no comma-joined conditions, bounded loops).

## 4. The app

- **Load:** after a clean load, if `addingMissingShippedLanguages()` returns a configuration, save it once (never when the file had problems).
- **Memory:** `TargetMemory` wraps UserDefaults (`[String: String]` under `targetBySource`); read when resolving, written on every choice from the picker or the menu.
- **Popup:** `.choosingDirection` carries the source (or `nil`). With a source: "Translate into:" with the candidates. Without one and three or more languages: "Which language is this?" with all enabled languages, then the target step. The header shows a `Menu` of `TargetChoice.menuTargets` when `usesMenu`, else today's Swap button.
- **Setup window:** its English sample translates English → the remembered target for English, or the first other enabled language, so enabling a third language never breaks the setup test.
- **Glossary settings:** columns for enabled languages only.

## 5. Golden set

`evals/golden/translation.json` gains 20 cases: `en-fr`, `fr-en`, `en-it`, `it-en`, five each, synthetic, with invented proper nouns (as the existing cases), at least one per direction with a do-not-translate term and one with a profile. References written in standard French and Italian. `correction.json` is untouched.

## 6. Tests

- Resolver: two languages unchanged; three with and without a remembered target; a remembered target that is no longer enabled is ignored; the source is carried.
- `direction(from:into:)`: given source; nil source with two and with three languages; target equal to source; disabled target.
- `addingMissingShippedLanguages`: missing fr/it appended disabled; `fr-CH` present suppresses `fr`; nothing missing gives `nil`; existing entries and order untouched.
- Constraints: the recognizer is given the enabled base codes (a recording fake); enabling a language changes them.
- `TargetChoice`: menu targets exclude the source and disabled languages; `usesMenu` at two and three.
- Golden set: every direction string parses; an unknown code is refused; the locale-rule check fires for de-CH targets and not for fr/it/en.
- The existing "two invented codes" resolver test stays, extended to three.

## 7. Manual checks (yours)

| # | Do | Expect |
|---|---|---|
| L1 | Launch with your current config | Settings › General lists French and Italian, switched off; `config.json` now has them with `"enabled": false`; everything else unchanged |
| L2 | Translate English and German texts | Exactly as before, Swap included |
| L3 | Enable French; translate a French paragraph | "Translate into:" English / Swiss Standard German; pick German; the header reads "French → Swiss Standard German ▾" |
| L4 | Translate another French text | Goes straight to German; the header menu switches it to English and re-runs |
| L5 | Translate a short ambiguous text ("ciao") | "Which language is this?" then the target |
| L6 | Enable Italian too; Run Setup Guide… to the test step | The sample translates |
| L7 | Disable French and Italian again | Back to two languages: Swap button, no pickers |

**Risk to your setup:** L1 writes `config.json` once (two entries appended). Back it up first if you like (Settings › General › Show config.json in Finder); deleting the two entries brings them back on the next launch, switched off.
