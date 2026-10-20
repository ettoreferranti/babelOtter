# History retention, off and Clear All — implementation plan

**Spec:** `docs/superpowers/specs/2026-10-20-history-retention-design.md` (#69). **Branch:** `feat/history-retention`.

Each task ends with `swift build` and `swift test` green and one commit. Kit code follows spec 3.5.

| # | Task | Files | Tests |
|---|---|---|---|
| 1 | `HistoryRetention`; `Configuration.retentionDays` becomes it | `Config/HistoryRetention.swift`, `Configuration.swift` | `HistoryRetentionTests`; `ConfigurationStoreTests`, `ConfigurationReloadTests` updated |
| 2 | `HistoryPolicy` | `History/HistoryPolicy.swift` | `HistoryPolicyTests` |
| 3 | `deleteOlder`, `deleteAll`, `count` in both stores | `HistoryStore.swift`, `SQLiteHistoryStore.swift` | contract tests; raw-byte tests |
| 4 | Whole-line history problems (`opening`, `saving`, `pruning`, `clearing`); readiness cause shows the line; `HistoryBrowser.clearAll`, `count`, `.clearing` | `HistoryProblem.swift`, `ReadinessPolicy.swift`, `HistoryBrowser.swift` | `HistoryProblemTests`, `ReadinessPolicyTests`, `HistoryBrowserTests` |
| 5 | Mutation gate: the two new files join PASS1 | `.github/workflows/mutation.yml` | - |
| 6 | App: `ConfigurationSource.isFallback`; `HistoryRecorder` policy and pruning; `AppDelegate` wiring; menu note; window note and Clear All | app target | build; manual C1-C5 |
| 7 | `PRIVACY.md` (journal limit), HANDOFF (C1-C5), README | docs | - |

Then a fresh-context review of the branch, fixes, and the manual checks (yours) before a PR.
