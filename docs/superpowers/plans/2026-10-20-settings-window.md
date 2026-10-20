# Settings window (first PR) — implementation plan

**Spec:** `docs/superpowers/specs/2026-10-20-settings-window-design.md` (#61, #60). **Branch:** `feat/settings-window`.

Each task ends with `swift build` and `swift test` green and one commit. Kit code follows spec 3.4. Refusals use plain `throws` (not typed throws), to stay clear of toolchain differences on CI's Swift 6.1.

| # | Task | Files | Tests |
|---|---|---|---|
| 1 | `SettingsRefusal`; `SettingsEditor` for languages, retention, timeout, clipboard, models | `Settings/SettingsEditor.swift` | `SettingsEditorTests` incl. round-trip through the file encoding |
| 2 | `HotKeyText`; `SettingsEditor.setHotKey` (parse, resolve, clash with each other action's resolved hotkey, so the refusal lands on the edited row) | `Settings/HotKeyText.swift`, `SettingsEditor.swift` | `HotKeyTextTests`, more `SettingsEditorTests` |
| 3 | `ModelChoice` | `Settings/ModelChoice.swift` | `ModelChoiceTests` |
| 4 | Mutation gate: the three files join PASS1 | `.github/workflows/mutation.yml` | - |
| 5 | App: `ConfigurationSource.fileProblems`; `AppDelegate` suspend/resume hotkeys and a reload hook; `Settings/` window controller, model, General, Models (with download), Hotkeys (recorder) views; Settings... in the menu | app target | build; manual S1-S8 |
| 6 | HANDOFF (S1-S8), README | docs | - |

Then a fresh-context review, fixes, and the manual checks (yours) before a PR.
