# Learning goal, streak and milestones — implementation plan

**Spec:** `docs/superpowers/specs/2026-11-11-learning-goal-design.md` (#136). **Branch:** `feature/learning-goal`.

Each task ends with `swift build` and `swift test` green and one commit. Kit code follows the mutation gate's source rules (ASCII only, no comma-joined conditions, no comparison with an enum member in a condition, bounded loops, no logic in closures); new kit files join PASS1.

One thing the spec left to the build: a popup writes its History record when it closes, not when the result arrives. So the popup line is a **preview** of what the record will do to the log (the same pure function, on the log as it is), and the log itself changes only when the record is saved.

| # | Task | Files | Tests |
|---|---|---|---|
| 1 | `LearningSettings`; `Configuration.learning` / `learningSettings`; `SettingsEditor.setLearning(enabled:)`, `setLearningDays(_:)` | `Config/LearningSettings.swift`, `Config/Configuration.swift`, `Settings/SettingsEditor.swift` | absent, partial, valid and invalid `learning`; the file is not rewritten; refusals |
| 2 | `LearningDay`, `LearningLog`, `Milestone` | `Learning/LearningLog.swift`, `Learning/Milestone.swift` | day from a date and calendar; sorted, unique, 400 bound; JSON round trip; titles |
| 3 | `LearningRules`: learning action, week and streak, milestones, the outcome and its line, next count milestone | `Learning/LearningRules.swift` | every rule of spec section 2 |
| 4 | `TranslateHint` | `Learning/TranslateHint.swift` | directions, word floor, once a day, wording |
| 5 | Privacy panel line; mutation file list | `Privacy/PrivacyReport.swift`, `.github/workflows/mutation.yml` | the line on and off |
| 6 | App: `LearningTracker` (the log in preferences), `HistoryRecorder.onSaved`, popup line and hint, Progress section with Reset, Settings > General, Privacy window | app target | build; manual checks |
| 7 | HANDOFF (manual checks), README, PRIVACY.md | docs | - |

Then `Tools/mutate.sh`, a fresh-context review, fixes, and the manual checks (yours) before a PR.
