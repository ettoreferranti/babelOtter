# First-run setup and re-presented steps — design

**Status:** approved in conversation 2026-10-22, pending review of this document.
**Milestone:** M3. **Covers:** #70 and #71 (epic #13), in one PR: one setup window, opened at the start on a fresh install and at a single step when a permission is later missing. **Parent spec:** `2026-09-18-babelotter-design.md` section 4.12 (`FR-ONB-01`, `FR-ONB-02`).

## 1. What it does

### 1.1 The setup window (#70)

A window titled **Set Up lingoSwen**: the five steps in a sidebar, the current one on the right, **Back** and **Continue** at the bottom. Each step checks itself; **Continue** stays disabled, with the reason beside it, until the step's condition holds. A step that is already satisfied when reached shows its check and can be passed straight away.

| Step | Shows | Continue when |
|---|---|---|
| 1. Accessibility | Why it is needed (to read the selection and paste the result); **Open Accessibility Settings** (asks macOS to show its prompt, then opens the pane). The status is re-checked every second while the step is shown, so granting it is noticed without a restart | `AXIsProcessTrusted()` |
| 2. Ollama | Whether Ollama answers on this Mac. Not running: **Start Ollama** (as the menu's remedy does). Not installed: **Get Ollama**, which opens ollama.com/download in the browser. Re-checked every 2 seconds while shown | The probe reaches the daemon |
| 3. Model | A pop-up of the installed models, the configured one preselected (`Configuration.defaultModel` on a fresh install); a model that is not installed shows **Download...**, which asks first and shows progress (the Models tab's code). The choice is written for every action | The chosen model is installed |
| 4. Hotkeys | The four recorders from Settings, with their defaults; the same refusals | Always (the defaults are fine) |
| 5. Try it | An editable English sentence ("Please register for the module by Friday.") and **Translate**: the real pipeline into the other enabled language, streamed. A failure shows its message and **Translate** can be pressed again | A translation finished |

**Finish** on the last step records that setup is done and closes the window.

### 1.2 When it appears

- **Fresh install:** no `config.json` at launch (the configuration is then written with the defaults, as today) and setup not recorded as done: the window opens at step 1 after launch. The first-launch system Accessibility prompt is no longer shown on its own; step 1 asks for it.
- **Existing install:** `config.json` already existed at launch: setup counts as done and nothing appears.
- **Any time:** **Setup Guide...** in the menu opens the window at step 1.
- **Not finished:** a fresh install that closes the window before Finish sees it again at the next launch.

### 1.3 A permission later missing (#71)

When Accessibility is missing and an action is triggered (hotkey or menu), the setup window opens **at the Accessibility step only** (no sidebar, no other steps), instead of today's popup message. It re-checks every second; once granted it shows "Granted - try the action again." and **Done** closes it. The menu bar's blocked state is unchanged (it already shows blocked when Accessibility is missing). Ollama stopping later is not a permission and keeps its existing handling (the menu's readiness line and the popup's error).

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| Who sees the wizard | Fresh installs only; Setup Guide... for anyone | An existing working install should not be interrupted |
| How "fresh" is known | No `config.json` at launch, and no `setupCompleted` flag in `UserDefaults` | The file's absence is the existing first-launch signal; the flag survives a deleted config |
| Revoked permission | The window at that one step, replacing the popup message | One place that explains and verifies; it closes itself when done |
| Live test | A sample translated in the window | Exercises the model, prompts and parsing for real; reading another app's selection depends on steps 1 and 4, which are verified there |
| Re-checking | Timers while a step is shown (1 s Accessibility, 2 s Ollama), stopped when the window closes | macOS posts no notification for an Accessibility grant |

## 3. The kit (`Sources/BabelOtterKit/Setup/`)

- `SetupStep`: `.accessibility, .ollama, .model, .hotkeys, .tryIt`, with titles.
- `SetupFacts`: `accessibilityGranted`, `daemon: DaemonProbe?` (nil while checking), `chosenModel`, `testSucceeded`.
- `SetupFlow.blocker(for step: SetupStep, facts: SetupFacts) -> String?`: nil when the step may be left forward, otherwise the reason shown beside Continue ("Grant Accessibility to continue.", "Ollama isn't running.", "Checking Ollama...", "<model> is not installed.", "Translate the sentence to finish."). All wording here, tested.
- `SetupGate.shouldOpen(configurationExisted: Bool, setupCompleted: Bool) -> Bool`: true only for no file and not completed.
- `SetupFlow.sampleSentence`.

## 4. The app (`Sources/BabelOtterApp/Setup/`)

- `SetupWindowController` (an `AppWindow`, presented in front): `show(from: .start)` and `show(only: .accessibility)`.
- `SetupModel`: the facts, refreshed by timers while the relevant step shows; the model choice and download through the same `SettingsEditor` and pull code as Settings; the try-it run through `Translator`, streamed.
- `AppDelegate`: decides at launch with `SetupGate`; replaces `showAccessibilityNeeded` with the window at the Accessibility step; drops the standalone first-launch prompt; adds **Setup Guide...** to the menu. `UserDefaults` key `setupCompleted`.

## 5. Out of scope

- Re-presenting other steps automatically (Ollama, model): their failures already show in the menu and the popup.
- Signing, notarizing and distributing (#82).

## 6. Testing

- **`SetupFlowTests`**: each step's blocker for each fact (granted or not; probe nil, unreachable, reachable; model installed or not; test done or not); hotkeys never block; every message's wording.
- **`SetupGateTests`**: the four combinations.

### Manual (in HANDOFF)

| # | Do | Expect |
|---|---|---|
| O1 | Quit; move `config.json` aside and `defaults delete ch.lingoswen setupCompleted`; start lingoSwen | The setup window opens at Accessibility (already granted: a check, Continue enabled) |
| O2 | Walk the steps: Ollama check; Model (keep the default); Hotkeys (keep); Try it: Translate | Each step shows its check; the translation streams in; Finish closes the window |
| O3 | Quit and start again | No setup window |
| O4 | Revoke lingoSwen in System Settings, Privacy and Security, Accessibility; press Control-Option-T on a selection; re-grant it | The setup window opens at Accessibility only; after re-granting it says "Granted - try the action again."; Done closes it; the hotkey works again without a restart |
| O5 | Choose Setup Guide... in the menu | The window opens at step 1 |
| O6 | Restore your `config.json` (move it back) and restart | Your settings are back |
