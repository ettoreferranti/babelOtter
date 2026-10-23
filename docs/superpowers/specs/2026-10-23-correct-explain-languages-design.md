# Correct and Explain beyond German — design

**Status:** approved in conversation 2026-10-23, pending review of this document.
**Milestone:** M4. **Covers:** the second and last PR for #81 (epic #15): the two two-language assumptions left after #117, Correct (German only) and Explain (German into English). **Parent spec:** `2026-10-23-more-languages-design.md`.

## 1. What it does

- **"My language"**, a new setting in Settings › General, chosen from the enabled languages and English by default. The model writes its explanations in it: Correct's note for each error, and Explain's summary and notes. It is also the language the author "thinks in" when Correct looks for false friends.
- **Correct works on any enabled language.** The text's language is detected. A text in my language is proofread as a native speaker's text, with no learner or false-friend framing. Any other enabled language is corrected as a language the author is learning, with false friends judged against my language.
- **Explain works on any enabled language except my language.** It explains the text in my language. A text already in my language is refused: "This is already in English."
- **When detection is unsure** (too short, or below the floor) and exactly one enabled language is not my language, that one is assumed. With English and German enabled and English as my language, that is German, as today. Exception (revised after review): a below-floor guess that names another candidate, e.g. English for Correct, is a real doubt and the popup asks. On main, Correct refused such a text instead. Otherwise the popup asks "Which language is this?", the step #117 added. A confident guess outside the enabled languages is refused as now.
- **Per-language correction notes** are data on each language, sent to the model with Correct's prompt. German keeps today's examples (case after prepositions, pronouns without gender), moved out of the code. French and Italian get their own: agreement of past participles and adjectives, accents, elision, and for Italian articulated prepositions. English gets none.
- **The golden set** gains 10 synthetic correction cases for French and 10 for Italian. Correction cases name their language; the existing 38 remain German.
- **The app's own wording stays English**, like the whole interface, e.g. Correct's rule note "Swiss Standard German writes ss, never ß". Only what the model writes follows my language.

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| Correct scope | Any enabled language; my language proofread as native | One action for every language; a native text still has typos |
| Explanation language | One "My language" setting for Correct's notes and Explain | One notion of "the language I read best" |
| Explain scope | Any enabled language but mine | Explaining a text in my own language into my own language is a rewording, not an explanation |
| Unsure detection | The one enabled language that is not mine, if there is exactly one; else ask | Keeps today's behaviour for English and German; asks only when there is a real choice |
| Prompt specifics | Per-language `correctionNotes` as data, shipped for de, fr and it | Languages stay data (`FR-LNG-03`); German loses nothing |
| Quality | 10 + 10 golden correction cases | French and Italian correction quality is measured, not assumed |
| JSON keys | `explanation_en` becomes `explanation`; `summary_en` becomes `summary` | The keys named a language that is now a setting |
| Disabling my language | Refused in Settings: "English is your language; choose another first." | My language must stay enabled to be detected and offered |

## 3. Configuration

- `Configuration.myLanguage: LanguageCode?`, key `myLanguage`. A file without the key gets English while it is on, else the first enabled language (revised after review: a file with English off must not become a problem). A named base code finds its configured region (`de` is `de-ch`). Only a named code that is not an enabled language is a configuration problem naming the field.
- `LanguageConfig.correctionNotes: String?`, key `correctionNotes`. Absent from a file means the shipped notes for the same code or base code, as `addressForms` does. `null` means none. Shipped for `de-CH`, `fr` and `it`.
- `SettingsEditor.setMyLanguage(_:)`: the code must be enabled. `setLanguage(_, enabled: false)` on my language is refused with `.isMyLanguage`.
- `Configuration.germanLanguage` goes. Its callers ask for the text's language or my language instead.

## 4. The kit

- `TextLanguage` (`Text/TextLanguage.swift`), pure. `resolve(_ detection: Detection, configuration:, excludingMine: Bool) -> Result<LanguageCode, TranslationError>`:
  - confident and enabled: that language (as configured, base-code match);
  - confident and not enabled: `.languageNotConfigured`;
  - unsure: the one enabled language that is not mine, if there is exactly one, unless a below-floor guess names a different candidate; otherwise ask.
  The candidates to ask about are the enabled languages, without my language when `excludingMine`. An exact code match wins over a base-code match. (The code returns its own `TextLanguageResolution` rather than `Result`.) Correct passes `false`, Explain `true`. For Explain, a confident guess of my language is `ExplanationFailure.alreadyMine(language)`.
- `Corrector.language(for:)` and `Explainer.language(for:)` wrap it. `correct(_:in:profile:styleNote:)` and `explain(_:in:...)` take the language. The German-only gates go: `CorrectionFailure.notGerman` and `ExplanationFailure.notGerman` are replaced by the resolution above and `alreadyMine`.
- `PromptBuilder`:
  - Correct names the language, and "learning X and often thinks in Y" when X is not my language. Otherwise it says "a native speaker's text; correct errors only". The language's `correctionNotes` follow, and explanations are "in Y".
  - Explain reads "Explain the X text below in plain Y".
  - The JSON keys are renamed (section 2); the parser and the partial-field streaming follow.
- `ResponseContracts`: `explanationEn` becomes `explanation`, `summaryEn` becomes `summary`.
- `HistoryRecord`: Explain records the text's language → my language; Correct records the text's language.
- Eval:
  - `CorrectionCase.language`, key `language`, default `de-ch`, any shipped code.
  - The runner corrects each case in its language, with my language `en`.
  - `EvalFailure.notGerman` becomes `wrongLanguage`. The summary's JSON reads either name, so earlier reports still load.

All new or changed kit files follow the mutation gate's rules, and `TextLanguage` joins pass 1.

## 5. The app

- **Settings › General:** a "My language" picker over the enabled languages, under the language toggles. The menu shows the refusal when disabling my language.
- **Popup:**
  - Correct and Explain resolve the language first, as Re-pitch does: a known language runs; unsure asks "Which language is this?" (`choosingSource`), then runs.
  - The refusals read "This looks like X, which is not one of your languages." and "This is already in Y."
  - `writingLanguage` for Correct is the text's language.
- **History rows** show the recorded languages; nothing else changes.

## 6. Golden set

`evals/golden/correction.json` gains 10 French and 10 Italian cases. They are synthetic, with invented proper nouns, and carry `"language": "fr"` or `"it"`. Each has one to three planted errors from the categories, at least two clean cases per language, and at least one `mustNot` guard per language. Typical errors:
- French: participle agreement, *à* versus *a*, a missing elision, *ces* versus *ses*, accents;
- Italian: articulated prepositions, *è* versus *e*, double consonants, agreement, *perché*.

## 7. Tests

- `TextLanguage`:
  - confident (enabled, base-code match, not enabled);
  - unsure with one, two or no candidates;
  - `excludingMine` on and off;
  - unchanged results for en and de-CH with English as my language.
- Configuration:
  - `myLanguage` absent gives `en`; an invalid value is a problem naming the field;
  - `correctionNotes` fill by base code, `null` gives none;
  - the editor refuses disabling my language and setting a disabled one.
- Prompts: Correct for German-as-learned, French-as-learned and English-as-mine, each naming the right languages, notes and explanation language; Explain names both languages; the new keys.
- Corrector and Explainer:
  - a French text is corrected in French, with explanations in my language;
  - Explain on my language is `alreadyMine`;
  - an unsure short text resolves or asks per the rule.
- Golden files: every case's language parses; French and Italian each have at least 10 cases, two of them clean.
- History records the right languages.

## 8. Manual checks (yours)

| # | Do | Expect |
|---|---|---|
| C1 | With today's setup (English as my language, en + de on), Correct and Explain a German text, and Correct a short German fragment | As before: corrections with English notes; an English explanation; the fragment is not asked about |
| C2 | Enable French; Correct a French text with two errors | Corrected in French; notes in English |
| C3 | Explain a French text | An English explanation of the French |
| C4 | Explain an English text | "This is already in English." |
| C5 | Correct an English text with a typo | Proofread; no learner or false-friend notes |
| C6 | Set My language to Italian; Correct a German text | Notes in Italian |
| C7 | Try to switch off the language set as My language | Refused with the message |
| C8 | Correct a short ambiguous text with en, de, fr on | "Which language is this?", then the correction |

**Risk to your setup:** the first save from Settings writes `myLanguage` into `config.json`; until then the file is untouched, because a missing key means English. Choosing another My language changes the language of Correct's and Explain's notes; set it back to English to undo.
