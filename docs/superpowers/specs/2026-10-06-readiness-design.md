# Readiness — design

**Status:** approved in conversation 2026-10-06, pending review of this document.
**Milestone:** M1b Translate UX. **Covers:** #28, #29, and the hotkey-failure bug noted on #26 (epic #3).
**Parent spec:** `docs/superpowers/specs/2026-09-18-babelotter-design.md`, sections 4.9 (`FR-UI-03`) and 4.12 (`FR-ONB-02`).

## 1. What it does

babelOtter never looks silently broken.

- **The menu bar icon shows readiness at a glance.** The otter alone means ready. A triangle after it means degraded: Ollama is not running, a model is missing, or a hotkey is taken. A stop sign after it means blocked: Accessibility is not granted, so nothing can be read.
- **The menu names each cause** in plain words, worst first, and offers "Open Accessibility Settings…" when that is the problem.
- **Triggering an action without Accessibility** opens the popup with an explanation and an **Open System Settings** button, instead of doing nothing.
- **The status stays current:** it is checked every 30 seconds, and also on menu open, on every action, and on wake.

## 2. Decisions

| Question | Decision | Why |
|---|---|---|
| Ollama unreachable | **Degraded**, not blocked. Changes `DaemonStatus.readiness` | Blocked means only "babelOtter cannot work until you change a system setting". Ollama is usually just not started, and the menu names it (#29) |
| When to check | Every 30 s, plus menu open, action trigger and wake | The icon is useful only if current when glanced at. One loopback request per 30 s costs nothing that matters |
| Icon | `🦦` alone when ready; `🦦` + `exclamationmark.triangle` when degraded; `🦦` + `xmark.octagon.fill` when blocked. Monochrome template symbols | The app stays recognisable, and a problem adds a mark. Colour can be added later if the mark proves too easy to miss |
| Action without Accessibility | The popup explains and links to System Settings | It appears where the user is already looking, and does not activate babelOtter (#48). An alert would steal focus; a notification needs a new permission |
| System prompt | First launch only (UserDefaults flag) | After the grant, nothing interrupts (#28) |
| Structure | A pure policy in the kit, a thin monitor in the app (approach 1) | The rules are tested and mutation-gated; AppKit stays small. Undocumented system notifications (approach 3) were rejected as fragile |
| Models checked | Translate's and Correct's, the actions that exist | Correct may use a different model from Translate; today only Translate's is checked |
| A hotkey already taken | **Degraded**, with its own cause line | Fixes the #26 bug, where the message was overwritten by the Ollama status |

## 3. Kit (`BabelOtterKit`) — pure, test-first, mutation-gated

### 3.1 `ReadinessPolicy` — `Sources/BabelOtterKit/Readiness/ReadinessPolicy.swift`

`Readiness` moves here from `DaemonStatus.swift`, unchanged (`ready`, `degraded`, `blocked`). It gains `Comparable`, ordered `ready < degraded < blocked`, so "worst" is `max`.

```swift
public struct HotKeyFailure: Sendable, Equatable {
    public let action: Action
    public let combination: String   // "Control-Option-T"
}

public struct ReadinessFacts: Sendable, Equatable {
    public let accessibilityGranted: Bool
    public let probe: DaemonProbe
    public let models: [Action: String]   // the actions being checked, in Action.allCases order
    public let takenHotKeys: [HotKeyFailure]
}

public enum ReadinessCause: Sendable, Equatable {
    case accessibilityMissing
    case ollamaUnreachable(detail: String)
    case modelMissing(action: Action, model: String)
    case hotKeyTaken(HotKeyFailure)

    public var readiness: Readiness   // blocked for accessibilityMissing, degraded for the rest
    public var detail: String
}

public struct ReadinessReport: Sendable, Equatable {
    public let readiness: Readiness       // max of the causes' readiness, or .ready when there are none
    public let causes: [ReadinessCause]
}

public struct ReadinessPolicy: Sendable {
    public func report(for facts: ReadinessFacts) -> ReadinessReport
}
```

**Rules:**

- `accessibilityGranted == false` gives `accessibilityMissing`.
- An unreachable probe gives **one** `ollamaUnreachable`, however many actions are checked. No `modelMissing` is reported then: whether a model is installed cannot be known.
- A reachable probe gives one `modelMissing` for each action whose model is not in the list. The match is exact, tag included, as in `DaemonStatusPolicy`. Two actions sharing a missing model give two causes, because each names what stops working.
- Each `HotKeyFailure` gives one `hotKeyTaken`.
- **Order:** `accessibilityMissing`, then `ollamaUnreachable`, then `modelMissing` by `Action.allCases` order, then `hotKeyTaken` by `Action.allCases` order. Blocked always comes first.

**Details** (shown as menu lines, so short):

| Cause | Detail |
|---|---|
| `accessibilityMissing` | "Accessibility is not granted, so babelOtter can't read your selection." |
| `ollamaUnreachable(d)` | "Ollama is not reachable: `d`." |
| `modelMissing(a, m)` | "`<Action>`: the model `m` is not installed." |
| `hotKeyTaken(f)` | "`<combination>` is taken by another app. Use the menu for `<Action>`." |

`<Action>` is the action's display name. `Action` gains `public var displayName: String` ("Translate", "Correct", "Explain", "Re-pitch") in `Configuration.swift`.

Like `DaemonStatusPolicy`, it holds no state: every report is computed from the facts in front of it, so recovery needs no restart.

### 3.2 `DaemonStatus` change

`DaemonStatus.readiness` maps `.unreachable` to **`.degraded`**. The doc comment is rewritten to say why: blocked is reserved for a missing system permission. Its tests change with it.

### 3.3 `OllamaClient.probe()`

```swift
public func probe() async -> DaemonProbe
```

One `/api/tags` request, classified exactly as `health(configuredModel:)` does today. `health` is rebuilt as `probe()` followed by `DaemonStatusPolicy`, with no change in behaviour.

## 4. App (`BabelOtterApp`) — checked by use

### 4.1 `ReadinessMonitor` — `Sources/BabelOtterApp/ReadinessMonitor.swift`

`@MainActor @Observable`. Publishes `report: ReadinessReport`.

- `refresh()` gathers the facts: `AXIsProcessTrusted()`, `client.probe()`, the models for `.translate` and `.correct` from the configuration (falling back to `Configuration.defaultModel`), and `takenHotKeys`. It then runs `ReadinessPolicy`. A refresh already in flight is joined, not duplicated.
- `takenHotKeys` is set once by `AppDelegate` after registering the hotkeys.
- **Triggers:** launch; a `Task` loop every 30 s; `NSWorkspace.didWakeNotification`; menu open (`NSMenuDelegate.menuWillOpen`); every action trigger. Menu open shows the last report at once, and the lines update in place when the new one arrives.

### 4.2 Icon

`button.title` stays `🦦`. `button.image` is nil when ready, otherwise the SF Symbol for the state as a template image, placed after the title (`imagePosition = .imageTrailing`). The tooltip and accessibility label read "babelOtter: ready", or "babelOtter: blocked. `<first cause's detail>`".

### 4.3 Menu

The Ollama and Accessibility lines are replaced by a status section:

- a headline: "Ready", "Degraded" or "Blocked";
- one disabled line for each cause;
- "Open Accessibility Settings…" only when `accessibilityMissing` is a cause.

"Check Again" calls `refresh()`. The configuration-problem line and everything else stay as they are. The hotkey-taken messages no longer write into the Ollama line; they reach the menu only as causes, which is the #26 fix.

### 4.4 Action without Accessibility

`AppDelegate.startAction` keeps its `AXIsProcessTrusted()` guard, but on failure it:

1. shows the popup with a new `PopupModel.Phase.needsAccessibility`, without starting a capture;
2. calls `monitor.refresh()`, so the icon changes at the same moment.

The popup reads "babelOtter needs Accessibility permission to read your selection." and offers **Open System Settings** (default) and **Dismiss** (Escape). The button opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` and dismisses the popup.

`promptForAccessibilityIfNeeded()` runs at first launch only, guarded by the UserDefaults key `promptedForAccessibility`. It is never called from `startAction`.

## 5. Errors and edge cases

- **Probe hangs.** The client's existing timeout bounds it. The in-flight join means the 30 s loop never stacks probes.
- **Rebuilt, unsigned builds.** macOS ties the Accessibility grant to the code signature. A local rebuild can lose the grant, or list it as granted while `AXIsProcessTrusted()` returns false. Blocked straight after a rebuild is this, not a bug. #82 (signing) removes it.
- **Revocation while running** is covered by the same paths: the next check turns the icon blocked, and the next action shows the popup. Re-presenting the setup steps (`FR-ONB-02`, #71) is out of scope.
- **Popup during capture.** Unchanged: `needsAccessibility` is shown before any capture starts, so it never races the clipboard tier.

## 6. Testing

**Kit, unit tests** (`ReadinessPolicyTests`, plus updated `DaemonStatus` tests):

- all facts good → `.ready`, no causes;
- `Action.displayName` for every case;
- each cause alone, with its readiness and detail;
- Accessibility missing plus Ollama unreachable → blocked, Accessibility first;
- unreachable probe with two models → one `ollamaUnreachable`, no `modelMissing`;
- two actions sharing a missing model → two `modelMissing`, in `Action.allCases` order;
- model tag mismatch (`:latest` installed, `:24b` configured) → missing;
- two hotkey failures → two causes, in order;
- `DaemonStatus.unreachable.readiness == .degraded`.

**App, manual checks:**

1. Revoke Accessibility: within 30 s the icon shows the stop sign and the menu names the cause. Trigger an action: the popup explains, and its button opens the Accessibility pane.
2. Grant it again: the icon returns to ready within 30 s, and no dialog appears.
3. Stop Ollama: the triangle, with Ollama named. Start it: ready.
4. Configure Correct with a model that is not installed: the triangle, naming Correct.
5. A taken hotkey shows its own cause line. How to provoke it is still open: Carbon may allow two apps the same combination, so this may need a second running copy of babelOtter.

## 7. Out of scope

- Re-presenting setup steps when permission is revoked (#71) and the first-run walkthrough (#70).
- Configurable hotkeys (#26, beyond the bug fix).
- Offering to start Ollama or pull a missing model (`FR-OLL-02`, `FR-OLL-03`).
- Coloured icon states.
