# Correct and Explain beyond German — implementation plan

**Spec:** `docs/superpowers/specs/2026-10-23-correct-explain-languages-design.md` (#81, part 2). **Branch:** `feat/correct-explain-languages`.

Each task ends with `swift build` and `swift test` green and one commit. Kit code follows the mutation gate's source rules; new kit files join pass 1.

| # | Task | Files | Tests |
|---|---|---|---|
| 1 | `Configuration.myLanguage` (default `en`, validated); `LanguageConfig.correctionNotes` with shipped notes for de-CH, fr, it; `SettingsEditor.setMyLanguage`, `.isMyLanguage` refusal | `Config/`, `Settings/SettingsEditor.swift` | decode, fill, validation, editor refusals |
| 2 | `TextLanguage.resolve(_:configuration:excludingMine:)` | `Text/TextLanguage.swift` | the cases in spec 7 |
| 3 | JSON keys `explanation` / `summary`; Correct and Explain prompts name the languages, notes and explanation language | `LLM/PromptBuilder.swift`, `LLM/ResponseContracts.swift`, parser | prompt and parse tests |
| 4 | Corrector: `language(for:)`, `correct(_:in:...)`, no German gate | `Pipeline/Corrector.swift` | French corrected in French; unsure rule |
| 5 | Explainer: `language(for:)`, `explain(_:in:...)`, `alreadyMine` | `Pipeline/Explainer.swift` | French into my language; my language refused |
| 6 | History records the real languages; `germanLanguage` removed | `History/HistoryRecord.swift`, `Config/Configuration.swift` | history tests |
| 7 | Eval: `CorrectionCase.language`, `wrongLanguage` (old name still read); 10 fr + 10 it correction cases | `Eval/`, `babelotter-eval`, `evals/golden/correction.json` | parse, coverage |
| 8 | Mutation gate: `TextLanguage` in pass 1 | `.github/workflows/mutation.yml` | - |
| 9 | App: My language picker; Correct/Explain resolve first, ask when unsure; refusal wording | app target | build; manual C1-C8 |
| 10 | HANDOFF (C1-C8), README | docs | - |

Then a fresh-context review, fixes, and the manual checks (yours) before a PR.
