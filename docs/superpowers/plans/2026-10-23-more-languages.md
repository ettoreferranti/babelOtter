# French and Italian; Translate with any number of languages — implementation plan

**Spec:** `docs/superpowers/specs/2026-10-23-more-languages-design.md` (#81, first PR). **Branch:** `feat/more-languages`.

Each task ends with `swift build` and `swift test` green and one commit. Kit code follows the mutation gate's source rules (ASCII only, no comma-joined conditions, bounded loops); new kit files join PASS1.

| # | Task | Files | Tests |
|---|---|---|---|
| 1 | `LanguageConfig.french` / `.italian` shipped, disabled; `Configuration.addingMissingShippedLanguages()` | `Config/LanguageConfig.swift`, `Config/Configuration.swift` | shipped list, address-form fill, append/suppress/nil cases |
| 2 | Detection constrained to enabled languages | `Text/LanguageDetector.swift` | a recording fake sees the enabled base codes |
| 3 | Resolver with memory; the source carried; `TranslationError.directionUnknown(source:candidates:)`; `Translator.direction(for:remembered:)`, `direction(from:into:)` | `Text/TargetLanguageResolver.swift`, `Pipeline/Translator.swift`, callers | resolver and direction cases from spec 6 |
| 4 | `TargetChoice` | `Text/TargetChoice.swift` | menu targets, `usesMenu` |
| 5 | Golden set: data directions, locale-rule check, 20 new cases (the runner needs no change: translating only needs configured languages) | `Eval/GoldenSet.swift`, `Eval/TranslationScorer.swift`, `babelotter-eval/main.swift`, `evals/golden/translation.json` | parsing, refusal, rule check |
| 6 | Mutation gate: new files in PASS1 | `.github/workflows/mutation.yml` | - |
| 7 | App: write back appended languages on load; `TargetMemory`; popup source/target steps and header menu; setup sample direction; glossary columns for enabled languages | app target | build; manual L1-L7 |
| 8 | HANDOFF (L1-L7), README | docs | - |

Then a fresh-context review, fixes, and the manual checks (yours) before a PR.
