# Browse and search history — implementation plan

**Spec:** `docs/superpowers/specs/2026-10-20-history-window-design.md` (#68). **Branch:** `feat/history-window`.

Each task ends with `swift build` and `swift test` green and one commit. Kit code follows the constraints of spec 3.6.

| # | Task | Files | Tests |
|---|---|---|---|
| 1 | `HistorySearch`: `normalized`, `contains`, `matches` | `Sources/BabelOtterKit/History/HistorySearch.swift` | `HistorySearchTests` |
| 2 | `HistoryCursor`; `HistoryStore.page(matching:before:limit:)` replaces `recent` as the requirement, `recent` becomes an extension; `InMemoryHistoryStore.page` | `HistoryCursor.swift`, `HistoryStore.swift` | contract tests for paging, cursor and search (memory and SQLite, SQLite pending until 3) |
| 3 | `SQLiteHistoryStore.page`: registered `lingoswen_contains`, known-actions `IN` list, bound cursor | `SQLiteHistoryStore.swift` | contract tests pass for SQLite; literal `%`, `_`, `'`, `\`; NUL; unknown action does not shorten a page |
| 4 | `HistoryProblem.reading`; `HistoryBrowser` and `HistoryBrowserProblem` | `HistoryProblem.swift`, `HistoryBrowser.swift` | `HistoryBrowserTests`, `HistoryProblemTests` |
| 5 | `HistoryRow` | `HistoryRow.swift` | `HistoryRowTests` |
| 6 | Mutation gate: the four new files join PASS1 | `.github/workflows/mutation.yml` | - |
| 7 | App: `HistoryRecorder` exposes `store` and `onRecord`; `HistoryWindow`, `HistoryWindowController`, `HistoryWindowModel`, `HistoryView` in `Sources/BabelOtterApp/History/`; History... in the menu | app target | build; manual W1-W7 |
| 8 | HANDOFF update with W1-W7 and the seed command; README status line | `docs/HANDOFF.md`, `README.md` | - |

Then a fresh-context review of the whole branch, fixes, and the manual checks (yours) before a PR.
