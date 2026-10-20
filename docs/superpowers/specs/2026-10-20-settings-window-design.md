# Settings window — design

**Status:** approved in conversation 2026-10-20, pending review of this document.
**Milestone:** M3 Explain, Re-pitch & Polish. **Covers:** #61 (epic #11), in three PRs, and with it #60 (a model per action) and #59 (glossary and do-not-translate list). This document designs the window and the first PR in full, and the later two in outline; each later PR gets its own short design addendum before it is built.
**Parent spec:** `docs/superpowers/specs/2026-09-18-babelotter-design.md`, section 4.11 (`FR-CFG-01`, `FR-CFG-02`, `FR-CFG-03`), 4.8 (`FR-GLO-01`, `FR-GLO-02`, `FR-UI-02`).

## 1. What it does

- **Settings... in the menu** (above History...) opens one window with tabs in its toolbar, as macOS settings windows have: **General**, **Models**, **Hotkeys** in the first PR; **Audiences** in the second; **Glossary** in the third. Choosing it again brings the same window forward.
- **The file stays the truth.** Every change is written to `config.json` at once, through the existing `ConfigurationStore.save`; the existing watcher then applies it to the running app exactly as a hand edit is applied (#26). There is no Save or Apply button, and no restart. A hand edit made while the window is open shows in the window.
- **Invalid values are refused, never coerced.** A value that would not load is not written; the control shows why beneath it ("Between 5 and 600 seconds") and the file keeps its last good value.
- **Read-only while the file is broken.** While `config.json` has a problem (it cannot be read, or a value in it is wrong), the window shows that problem at the top with Show config.json in Finder, and every control is disabled. Nothing the window writes can overwrite a file you were half-way through editing; it becomes editable again as soon as the file reads cleanly.

### 1.1 General (first PR)

| Setting | Control | Rule |
|---|---|---|
| Languages | One switch per configured language, by display name | At least two stay on (Translate needs a pair): while only two are on, neither can be switched off |
| History | Pop-up: Keep for, Unlimited, Off; with Keep for, a number of days | Days 1 to 36,500 |
| Request timeout | Number field, seconds | 5 to 600 |
| Clipboard | Switch: "Never read the selection through the clipboard" (`strictCaptureOnly`) | - |

`detectionConfidenceFloor` and `minimumLengthForDetection` are tuning values for the detector, not settings; they stay file-only and the window says so in a footnote.

### 1.2 Models (first PR, #60)

- One row per action: Translate, Correct, Explain, Re-pitch, each with a pop-up listing the models installed in Ollama (`OllamaClient.installedModels()`), refreshed when the tab opens. The model in use is selected.
- A configured model that is not installed is listed too, marked "not installed", with a **Download** button. Download streams `OllamaClient.pull(model:)` and shows the status line and a progress bar (completed / total); the row becomes normal when it finishes. One download at a time; closing the window does not stop it; a failed download shows Ollama's reason.
- When Ollama is not reachable, the tab says so ("Ollama isn't running - start it to choose a model") and shows each action's model as text, unchangeable.
- An action whose model is not set in the file uses `Configuration.defaultModel` (`model(for:)`, as now). Choosing a model writes `models[action]`.

### 1.3 Hotkeys (first PR)

- One row per action with a **shortcut recorder**: click it, press the shortcut, and it is written to the file as text such as `control+option+T`, the format `HotKeySpec` already reads. **Clear** makes the action menu-only (JSON `null`); **Default** restores its default.
- While a recorder is listening, lingoSwen's own hotkeys are suspended, so pressing Control-Option-T records it rather than starting Translate. Escape cancels; a click elsewhere cancels.
- A recorded shortcut is refused, with the reason under the row, when it has no Command, Control or Option; when another action already has it; or when the key cannot be named on this layout. A shortcut that is also a system shortcut is accepted with the existing warning ("also a system shortcut, so pressing it runs both").

### 1.4 Later PRs (outline)

- **Audiences (second PR):** the list of profiles; add, rename, delete (not the last one; the id is derived from the first name and never changes), register (Sie/du), tone guidance, and preferred terms.
- **Glossary (third PR, #59):** glossary entries (source term, target term, direction from the enabled languages) and the do-not-translate list, each a table with add and delete.

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| How the PRs split | Shell with General, Models and Hotkeys; then Audiences; then Glossary | Each PR is usable on its own and reviewable; the shell carries the shared machinery |
| How a change applies | Written to `config.json` at once; the watcher reloads | One apply path for the window and a hand edit; no new state to keep in step |
| A broken file | The window is read-only until the file reads cleanly | Saving would replace the broken file with the configuration in use plus one edit |
| Hotkey input | A shortcut recorder, written as text | The macOS convention; the file stays readable and hand-editable |
| Detection tuning | Not in the window | Tuning values, not preferences; one wrong slider makes detection worse for every text |
| Where the rules live | `SettingsEditor` in the kit | Validation and the edits are tested and under the mutation gate; the app only displays them |

## 3. The kit (`Sources/BabelOtterKit/Settings/`)

### 3.1 `SettingsEditor`

A value type: the configuration in use, plus edits that return a new configuration or a refusal.

```swift
public struct SettingsEditor: Sendable, Equatable {
    public init(configuration: Configuration)
    public private(set) var configuration: Configuration

    public mutating func setLanguage(_ code: LanguageCode, enabled: Bool) throws(SettingsRefusal)
    public mutating func setRetention(_ retention: HistoryRetention) throws(SettingsRefusal)
    public mutating func setTimeout(seconds: Double) throws(SettingsRefusal)
    public mutating func setStrictCaptureOnly(_ on: Bool)
    public mutating func setModel(_ model: String, for action: Action) throws(SettingsRefusal)
    public mutating func setHotKey(_ binding: HotKeyBinding, for action: Action, layout: KeyLayout) throws(SettingsRefusal)
}

public enum SettingsRefusal: Error, Equatable {
    case tooFewLanguages            // "At least two languages stay on."
    case outOfRange(String)         // "Between 5 and 600 seconds"
    case emptyModel
    case hotKey(HotKeyProblem)      // the existing wording
    case sharedWith(Action)         // "Already used by Translate."

    public var message: String
}
```

- Each method validates before changing anything; a refusal leaves `configuration` as it was.
- `setHotKey(.text(...))` parses with `HotKeySpec.parse`, resolves with the layout, and checks the other actions' bindings through `HotKeyPlan.make`, so the window and the file follow the same rules.
- After every accepted edit, `configuration` round-trips through `JSONEncoder.configuration` and `JSONDecoder` to itself (a test, for every method), so nothing the window writes can fail to load.

### 3.2 `HotKeyText`

```swift
public enum HotKeyText {
    /// "control+option+T" for a pressed key, or nil when it cannot be named:
    /// the layout's character for the key code, else a `NamedKey`.
    public static func text(keyCode: UInt32, modifiers: UInt32, layout: KeyLayout) -> String?
}
```

The inverse of what `HotKeySpec.parse` and `KeyLayout.resolve` do, so a recorded shortcut reads back to the same combination (a test over every letter, digit and named key on a US and a Swiss German layout table).

### 3.3 `ModelChoice`

```swift
public struct ModelChoice: Equatable, Sendable {
    /// The installed models, sorted, plus the configured one when it is not installed.
    public let options: [String]
    public let isInstalled: Bool
    public init(configured: String, installed: [String])
}
```

### 3.4 Mutation gate and constraints

The three files join PASS1. The constraints of #67 to #69 apply.

## 4. The app (`Sources/BabelOtterApp/Settings/`)

- `SettingsWindowController`: one window, made once, `Settings...` in the menu; brings the app forward like History.
- `SettingsModel` (`ObservableObject`): holds a `SettingsEditor` built from `ConfigurationSource.configuration`; each control calls an editor method, then `store.save`; a refusal is kept per field and shown under it. On every configuration reload it rebuilds the editor, so a hand edit shows.
- `ConfigurationSource.fileProblems: [String]`: the load problems of the last read (not hotkey or watcher issues). Non-empty makes the window read-only.
- `HotKeyRecorderView`: an `NSViewRepresentable` around an `NSView` that becomes first responder, reads `keyDown` and `flagsChanged`, and asks `HotKeyText` for the text. `AppDelegate` gains `suspendHotKeys()` / `resumeHotKeys()` (unregister and re-register the current plan), called when a recorder starts and stops listening.
- `ModelDownload`: runs `pull(model:)` on a task owned by the controller, publishes progress, and refreshes the installed list on completion; `ReadinessMonitor.refresh()` follows so the menu's "model is not installed" line goes away.

## 5. Out of scope

- Audiences and Glossary tabs (later PRs, their own addenda).
- Adding or defining languages (a language is data with locale rules; it stays file-only, `FR-LNG-03`).
- Detection tuning values.
- Deleting installed models; choosing which Ollama to talk to (always loopback, `NFR-P4`).

## 6. Testing

### 6.1 Unit

- **`SettingsEditorTests`**: each method accepts a valid value and refuses each invalid one with its message, leaving the configuration unchanged; the last two languages cannot be switched off; retention days at 0, 1, 36,500 and 36,501; timeout at 4.9, 5, 600, 600.1; an empty model; hotkeys without a modifier, shared with another action, unknown key, `.off`, `.useDefault`; every accepted edit round-trips through the file's encoding.
- **`HotKeyTextTests`**: every letter and digit, F1 to F20, space, return, tab, escape, delete and arrows, with each modifier set, read back through `HotKeySpec.parse` and `KeyLayout.resolve` to the same key code and modifiers; a key with no character and no name gives nil.
- **`ModelChoiceTests`**: installed and sorted; a configured model not installed is listed and marked; an empty installed list.

### 6.2 Manual (in HANDOFF)

| # | Do | Expect |
|---|---|---|
| S1 | Choose Settings... in the menu | The window comes forward with General, Models and Hotkeys |
| S2 | General: switch off English; then set Keep for 30 days; then type 3 in the timeout | with only English and German configured, English cannot be switched off; `config.json` shows `"retentionDays" : 30` at once; 3 is refused with "Between 5 and 600 seconds" and the file keeps its value |
| S3 | Models: choose another installed model for Explain; run Explain | `config.json` has it under `models`; Explain uses it |
| S4 | Write a model that is not installed into the file by hand; open Models | It is listed as not installed with Download; Download shows progress and the row becomes normal; the menu's missing-model line goes |
| S5 | Hotkeys: click Translate's recorder and press Control-Option-T; then Control-Option-C; then Shift-K | Control-Option-T records without starting Translate; Control-Option-C is refused as Correct's; Shift-K is refused for having no Command, Control or Option |
| S6 | Hotkeys: record Control-Shift-Y for Explain; select German text in Mail and press it | Explain runs |
| S7 | Break `config.json` by hand (a missing comma); look at the window; fix it | The window shows the problem and every control is disabled; after the fix it is editable again |
| S8 | Quit Ollama; open Models | "Ollama isn't running"; the models are shown as text |
