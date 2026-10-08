# Readiness — design

**Status:** approved in conversation 2026-10-06, pending review of this document.
**Milestone:** M1b Translate UX. **Covers:** #28, #29, and the hotkey-failure bug noted on #26 (epic #3).
**Revised 2026-10-08:** hotkey problems are detected against the system shortcuts (section 3.4), not as "taken by another app".
**Parent spec:** `docs/superpowers/specs/2026-09-18-babelotter-design.md`, sections 4.9 (`FR-UI-03`) and 4.12 (`FR-ONB-02`).

## 1. What it does

babelOtter never looks silently broken.

- **The menu bar icon shows readiness at a glance.** The otter alone means ready. A triangle after it means degraded: Ollama is not running, a model is missing, or a hotkey clashes with a system shortcut or could not be registered. A stop sign after it means blocked: Accessibility is not granted, so nothing can be read.
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
| A hotkey that cannot fire | **Degraded**, with its own cause line. Two problems: it matches an enabled system shortcut, or `RegisterEventHotKey` failed | Fixes the #26 bug, where the message was overwritten by the Ollama status |
| How to detect a clash | Compare against `CopySymbolicHotKeys()`, the system shortcuts in System Settings › Keyboard. Registration stays non-exclusive | Carbon hotkeys are non-exclusive: several apps may register the same combination and all are notified, so registration never fails because of another app, and no API lists other apps' hotkeys. `kEventHotKeyExclusive` would mute every other app's registration of the combination, and its header contradicts itself about when it fails. A system shortcut is the clash that actually breaks the hotkey |

## 3. Kit (`BabelOtterKit`) — pure, test-first, mutation-gated

### 3.1 `ReadinessPolicy` — `Sources/BabelOtterKit/Readiness/ReadinessPolicy.swift`

`Readiness` moves here from `DaemonStatus.swift`, unchanged (`ready`, `degraded`, `blocked`). It gains `Comparable`, ordered `ready < degraded < blocked`, so "worst" is `max`.

```swift
public struct HotKeyCombination: Sendable, Equatable {
    public let keyCode: UInt32
    public let modifiers: UInt32      // Carbon modifier bits (cmdKey, shiftKey, optionKey, controlKey)
    public let displayName: String    // "Control-Option-T"
}

public struct HotKeyFact: Sendable, Equatable {
    public let action: Action
    public let combination: HotKeyCombination
    public let registered: Bool       // RegisterEventHotKey returned noErr
}

public struct SystemShortcut: Sendable, Equatable {
    public let keyCode: UInt32
    public let modifiers: UInt32      // already converted to Carbon modifier bits (section 3.4)
    public let enabled: Bool
}

public struct ReadinessFacts: Sendable, Equatable {
    public let accessibilityGranted: Bool
    public let probe: DaemonProbe
    public let models: [Action: String]   // the actions being checked, in Action.allCases order
    public let hotKeys: [HotKeyFact]
    public let systemShortcuts: [SystemShortcut]
}

public enum ReadinessCause: Sendable, Equatable {
    case accessibilityMissing
    case ollamaUnreachable(detail: String)
    case modelMissing(action: Action, model: String)
    case hotKeyNotRegistered(action: Action, combination: String)
    case hotKeyClashesWithSystem(action: Action, combination: String)

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
- A `HotKeyFact` with `registered == false` gives `hotKeyNotRegistered`.
- A registered `HotKeyFact` whose combination equals an **enabled** `SystemShortcut` gives `hotKeyClashesWithSystem`. Equal means the same key code and the same modifier bits, comparing only command, shift, option and control. A disabled system shortcut is no clash.
- At most one hotkey cause per action: not registered wins, since a clash cannot matter then.
- **Order:** `accessibilityMissing`, then `ollamaUnreachable`, then `modelMissing` by `Action.allCases` order, then hotkey causes by `Action.allCases` order. Blocked always comes first.

**Details** (shown as menu lines, so short):

| Cause | Detail |
|---|---|
| `accessibilityMissing` | "Accessibility is not granted, so babelOtter can't read your selection." |
| `ollamaUnreachable(d)` | "Ollama is not reachable: `d`" |
| `modelMissing(a, m)` | "`<Action>`: the model `m` is not installed." |
| `hotKeyNotRegistered(a, c)` | "`<c>` couldn't be registered. Use the menu for `<Action>`." |
| `hotKeyClashesWithSystem(a, c)` | "`<c>` is also a system shortcut, so it may not reach `<Action>`. Change it in System Settings › Keyboard › Keyboard Shortcuts, or use the menu." |

No period follows the daemon's text, which may already end in one.

`<Action>` is the action's display name. `Action` gains `public var displayName: String` ("Translate", "Correct", "Explain", "Re-pitch") in `Configuration.swift`.

Like `DaemonStatusPolicy`, it holds no state: every report is computed from the facts in front of it, so recovery needs no restart.

### 3.2 `DaemonStatus` change

`DaemonStatus.readiness` maps `.unreachable` to **`.degraded`**. The doc comment is rewritten to say why: blocked is reserved for a missing system permission. Its tests change with it.

### 3.3 `OllamaClient.probe()`

```swift
public func probe() async -> DaemonProbe
```

One `/api/tags` request, classified exactly as `health(configuredModel:)` does today. `health` is rebuilt as `probe()` followed by `DaemonStatusPolicy`, with no change in behaviour.

### 3.4 System shortcut modifiers

`CopySymbolicHotKeys()` returns, for each system shortcut, a key code, a modifier value and an enabled flag. The header does not say how the modifiers are encoded. **Measured 2026-10-08** on macOS 26 (230 entries): they are **Carbon bits**. Command-Shift-3 is key code 20 with `0x300` (`cmdKey 0x100 | shiftKey 0x200`). Function and arrow keys also carry `0x20000` (`kEventKeyModifierFnMask`).

The conversion is a pure kit function, `SystemShortcut.carbonModifiers(fromSymbolic:)`: it keeps only the four compared bits (`0x100 | 0x200 | 0x800 | 0x1000`) and drops the rest, `0x20000` included. The kit cannot import Carbon (`NoUIImportsTests`), so the four values are written as literals there, with this measurement cited. The AppKit side only reads the dictionaries and passes the raw numbers through it.

## 4. App (`BabelOtterApp`) — checked by use

### 4.1 `ReadinessMonitor` — `Sources/BabelOtterApp/ReadinessMonitor.swift`

`@MainActor` final class. Holds `report: ReadinessReport?` (nil until the first check finishes) and calls `onChange` with each new report; `AppDelegate` is AppKit, so a callback is simpler than observation.

- `refresh()` gathers the facts: `AXIsProcessTrusted()`, `client.probe()`, the models for `.translate` and `.correct` from the configuration (falling back to `Configuration.defaultModel`), the hotkey facts, and the system shortcuts from `CopySymbolicHotKeys()`. It then runs `ReadinessPolicy`. Reading the system shortcuts on every refresh means a shortcut changed in System Settings shows up within 30 s, without a relaunch. A refresh already in flight is joined, not duplicated.
- The hotkey facts are set once by `AppDelegate` after registering the hotkeys. `HotKey` is unchanged: its non-exclusive registration already reports failure by returning nil, which `AppDelegate` records as `registered: false`.
- **Triggers:** launch; a `Task` loop every 30 s; `NSWorkspace.didWakeNotification`; menu open (`NSMenuDelegate.menuWillOpen`); every action trigger. Menu open shows the last report at once, and the lines update in place when the new one arrives.

### 4.2 Icon

`button.title` stays `🦦`. `button.image` is nil when ready, otherwise the SF Symbol for the state as a template image, placed after the title (`imagePosition = .imageTrailing`). The tooltip and accessibility label read "babelOtter: ready", or "babelOtter: blocked. `<first cause's detail>`".

### 4.3 Menu

The Ollama and Accessibility lines are replaced by a status section:

- a headline: "Ready", "Degraded" or "Blocked";
- one disabled line for each cause;
- "Open Accessibility Settings…" only when `accessibilityMissing` is a cause.

"Check Again" calls `refresh()`. The configuration-problem line and everything else stay as they are. The hotkey messages no longer write into the Ollama line; they reach the menu only as causes, which is the #26 fix.

### 4.4 Action without Accessibility

`AppDelegate.startAction` keeps its `AXIsProcessTrusted()` guard, but on failure it:

1. shows the popup with a new `PopupModel.Phase.needsAccessibility`, without starting a capture;
2. calls `monitor.refresh()`, so the icon changes at the same moment.

The popup reads "babelOtter needs Accessibility permission to read your selection." and offers **Open System Settings** (default) and **Dismiss** (Escape). The button opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` and dismisses the popup.

`promptForAccessibilityIfNeeded()` runs at first launch only, guarded by the UserDefaults key `promptedForAccessibility`. It is never called from `startAction`.

## 5. Errors and edge cases

- **Probe hangs.** The client's existing timeout bounds it. The in-flight join means the 30 s loop never stacks probes.
- **A clash is a warning, not a certainty.** When a system shortcut and babelOtter's hotkey share a combination, the system is expected to take the press. Manual check 5 confirms this; if babelOtter turns out to receive it anyway, the detail's "may not reach" wording stays true.
- **Menu shortcuts inside other apps** are not detected. No API lists them.
- **Ad-hoc-signed builds.** macOS ties the Accessibility grant to the code signature. `Tools/make-app.sh` signs with the stable "babelOtter Dev" identity when it exists, which keeps the grant; without it the build is signed ad hoc, and each rebuild loses the grant or lists it as granted while `AXIsProcessTrusted()` returns false. Blocked straight after such a rebuild is this, not a bug. #82 (signing) removes it for good.
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
- a hotkey matching an enabled system shortcut → `hotKeyClashesWithSystem`; the same shortcut disabled → no cause;
- same key code, different modifiers → no cause; modifier bits other than the four compared are ignored;
- a hotkey that is both unregistered and clashing → only `hotKeyNotRegistered`;
- two hotkey problems → two causes, in `Action.allCases` order;
- `SystemShortcut.carbonModifiers(fromSymbolic:)` against the measured values: `0x300` stays `0x300`, `0x21000` becomes `0x1000`, `0x1B00` (control, option, shift, command) is unchanged;
- `DaemonStatus.unreachable.readiness == .degraded`.

**App, manual checks:**

1. Revoke Accessibility: within 30 s the icon shows the stop sign and the menu names the cause. Trigger an action: the popup explains, and its button opens the Accessibility pane.
2. Grant it again: the icon returns to ready within 30 s, and no dialog appears.
3. Stop Ollama: the triangle, with Ollama named. Start it: ready.
4. Configure Correct with a model that is not installed: the triangle, naming Correct.
5. In System Settings › Keyboard › Keyboard Shortcuts, assign Control-Option-T to a system shortcut (for example a Screenshots entry). Within 30 s the triangle appears, with the clash named for Translate. Press Control-Option-T and note which one fires; record the result in `docs/architecture.md` section 7. Restore the shortcut: ready again within 30 s.

## 7. Out of scope

- Re-presenting setup steps when permission is revoked (#71) and the first-run walkthrough (#70).
- Configurable hotkeys (#26, beyond the bug fix).
- Offering to start Ollama or pull a missing model (`FR-OLL-02`, `FR-OLL-03`).
- Coloured icon states.
