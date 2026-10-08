# Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The menu bar icon shows whether babelOtter can work (ready, degraded, blocked), the menu names every cause, and an action triggered without Accessibility explains itself in the popup instead of doing nothing.

**Architecture:** A pure `ReadinessPolicy` in the kit turns facts (Accessibility granted, one Ollama probe, the model per action, hotkey registration, the system shortcuts) into a report: the worst readiness and a list of causes, worst first. A thin `ReadinessMonitor` in the app gathers those facts every 30 s and on menu open, action trigger and wake, and `AppDelegate` draws the icon and menu from each report. The popup gains a `needsAccessibility` phase.

**Tech Stack:** Swift 6 (tools 6.0), SwiftPM, Swift Testing, AppKit/SwiftUI (macOS 14), Carbon hotkeys and `CopySymbolicHotKeys`. Zero dependencies.

**Spec:** `docs/superpowers/specs/2026-10-06-readiness-design.md` (parent: `docs/superpowers/specs/2026-09-18-babelotter-design.md` sections 4.9 and 4.12).

## Global Constraints

- **Zero dependencies** (`DependencyAllowlistTests`).
- **One networking call site.** `NetworkingCallSiteTests` scans every file under `Sources/`, app included. No new or changed file may contain `URLSession`, `URLRequest`, `socket(`, `connect(`, `send(`, `recv(` or `(contentsOf:`, in code or in comments. Use `+=`, never `append(contentsOf:)`.
- **Kit sources are ASCII-only** (`AsciiSourceTests`). Write `"\u{203A}"` for the `›` separator in "System Settings › Keyboard". App sources are exempt.
- **The kit imports no UI framework** (`NoUIImportsTests`), Carbon included. Carbon modifier values appear in the kit as literals.
- **Every new kit file goes into `PASS1`** in `.github/workflows/mutation.yml`. The file-list check fails loudly otherwise.
- **muter traps** (see `docs/HANDOFF.md`):
  - no `while a < b, predicate` comma-conjunction;
  - no ternary whose condition ends in an enum member;
  - no `guard ... else { ...; return }` inside a `do` block inside a `Task` closure;
  - muter 16 drops mutants inside closures and nested loops and reports them as survivors, so kit rules are written as `for` loops calling named functions, not `compactMap`/`filter` closures. Before writing a test to kill a reported survivor, plant that mutant by hand.
- **User text is never logged, printed or persisted.** Nothing in this plan touches it.
- **Rigour by layer.** Kit tasks are TDD, with RED shown before GREEN. App tasks are verified by building (`swift build --product BabelOtterApp -Xswiftc -warnings-as-errors`), assembling (`Tools/make-app.sh`), launching and quitting, plus a manual check table for the user.
- **States:** blocked only for missing Accessibility; Ollama unreachable, a missing model, an unregistered hotkey and a hotkey clashing with a system shortcut are degraded.
- **Icon:** `🦦` alone when ready; `🦦` + `exclamationmark.triangle` (degraded); `🦦` + `xmark.octagon.fill` (blocked). Monochrome template images, after the title.
- **Checks:** every 30 s, on menu open, on every action trigger, on wake. A refresh in flight is joined, never duplicated.
- **Accessibility settings URL:** `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.
- **Hotkeys stay non-exclusive.** Control-Option-T translates (id 1), Control-Option-C corrects (id 2). Only Translate and Correct are checked.
- **System shortcut modifiers are Carbon bits** (measured 2026-10-08: Command-Shift-3 is key code 20, `0x300`; function and arrow keys add `0x20000`). Compare only `0x100 | 0x200 | 0x800 | 0x1000`.
- **Commit messages** end with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **A hung Ollama probe.** Refreshes must not stack behind it, and the icon must still update once the client's timeout ends it. Task 4, manual check M6.
2. **The menu open while a report lands.** The status lines are replaced in place, never duplicated or left stale. Task 4, manual check M7.
3. **Ollama's own error text ending in punctuation.** The cause detail must not read "refused.." or similar. Task 3 adds no period after the daemon's detail, and a test pins the exact string.
4. **A configuration with no model for Translate or Correct.** The default model is checked, not skipped. Task 4, manual check M8.
5. **Pressing the hotkey repeatedly without Accessibility.** Each press replaces the popup; popups never stack, and the capture path is never entered. Task 5, manual check M9.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/BabelOtterKit/Readiness/ReadinessPolicy.swift` (create) | `Readiness` (moved, now `Comparable`), hotkey and system-shortcut facts, `ReadinessCause`, `ReadinessReport`, `ReadinessPolicy` |
| `Sources/BabelOtterKit/LLM/DaemonStatus.swift` (modify) | `Readiness` removed from here; `.unreachable` becomes degraded |
| `Sources/BabelOtterKit/LLM/OllamaClient.swift` (modify) | `probe()`; `health` rebuilt on it |
| `Sources/BabelOtterKit/Config/Configuration.swift` (modify) | `Action.displayName` |
| `Tests/BabelOtterKitTests/Readiness/ReadinessPolicyTests.swift` (create) | |
| `Tests/BabelOtterKitTests/LLM/DaemonStatusTests.swift` (modify) | |
| `Tests/BabelOtterKitTests/LLM/OllamaClientTests.swift` (modify) | |
| `Sources/BabelOtterApp/ReadinessMonitor.swift` (create) | Gathers facts, runs the policy, publishes through `onChange`; reads the system shortcuts; opens the Accessibility pane |
| `Sources/BabelOtterApp/AppDelegate.swift` (modify) | Hotkey facts, icon, status lines, menu delegate, first-launch prompt, the `needsAccessibility` path |
| `Sources/BabelOtterApp/PopupModel.swift` (modify) | `Phase.needsAccessibility`, `requireAccessibility()`, `openAccessibilitySettings()` |
| `Sources/BabelOtterApp/PopupView.swift` (modify) | The explanation and its two buttons |
| `.github/workflows/mutation.yml` (modify) | PASS1 list |
| `docs/HANDOFF.md`, `docs/superpowers/specs/2026-10-06-readiness-design.md` (modify) | Status, manual checks; one spec wording fix |

---

### Task 1: Order readiness by severity, demote an unreachable daemon, name the actions

`Readiness` moves into its own folder, since it is no longer about the daemon alone, and gains an order so the worst of several is `max`. An unreachable Ollama becomes degraded (spec section 2). `Action` gains the name the menu shows.

**Files:**
- Create: `Sources/BabelOtterKit/Readiness/ReadinessPolicy.swift`, `Tests/BabelOtterKitTests/Readiness/ReadinessPolicyTests.swift`
- Modify: `Sources/BabelOtterKit/LLM/DaemonStatus.swift:9-14` (remove `Readiness`) and `:25-31` (`readiness`), `Sources/BabelOtterKit/Config/Configuration.swift:8-13`, `Tests/BabelOtterKitTests/LLM/DaemonStatusTests.swift`, `Tests/BabelOtterKitTests/LLM/OllamaClientTests.swift:203-211`, `.github/workflows/mutation.yml`

**Interfaces:**
- Produces: `public enum Readiness: Sendable, Equatable, Comparable, CaseIterable { case ready, degraded, blocked }` in `ReadinessPolicy.swift`; `Action.displayName: String`; `DaemonStatus.unreachable(...).readiness == .degraded`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/BabelOtterKitTests/Readiness/ReadinessPolicyTests.swift`:

```swift
import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Readiness")
struct ReadinessPolicyTests {

    @Test("readiness is ordered by severity, so the worst of several is the max")
    func orderedBySeverity() {
        #expect(Readiness.ready < Readiness.degraded)
        #expect(Readiness.degraded < Readiness.blocked)
        #expect([Readiness.degraded, .blocked, .ready].max() == .blocked)
    }

    @Test("every action has the name the menu shows")
    func actionDisplayNames() {
        #expect(Action.translate.displayName == "Translate")
        #expect(Action.correct.displayName == "Correct")
        #expect(Action.explain.displayName == "Explain")
        #expect(Action.repitch.displayName == "Re-pitch")
    }
}
```

In `Tests/BabelOtterKitTests/LLM/DaemonStatusTests.swift`, change `readinessLevels` and `recoversWithoutRestart`:

```swift
    // FR-UI-03: ready, degraded, blocked. Blocked is reserved for a missing
    // system permission, so nothing about the daemon is ever blocked.
    @Test("each status maps to the readiness the menu bar shows")
    func readinessLevels() {
        #expect(DaemonStatus.ready.readiness == .ready)
        #expect(DaemonStatus.modelMissing("m").readiness == .degraded)
        #expect(DaemonStatus.unreachable(detail: "x").readiness == .degraded)
    }
```

```swift
    @Test("recovery needs no intermediate state: the next probe decides")
    func recoversWithoutRestart() {
        let down = policy.status(probe: .unreachable(detail: "x"), configuredModel: "m")
        #expect(down.readiness == .degraded)
        let recovered = policy.status(probe: .reachable(models: ["m"]), configuredModel: "m")
        #expect(recovered == .ready)
    }
```

In `Tests/BabelOtterKitTests/LLM/OllamaClientTests.swift`, `healthNeverThrows`, change `#expect(status.readiness == .blocked)` to:

```swift
        #expect(status.readiness == .degraded)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "ReadinessPolicyTests|DaemonStatusTests|OllamaClientTests"`
Expected: build failure, `value of type 'Action' has no member 'displayName'` and `type 'Readiness' does not conform to 'Comparable'` (or the `<` operator not found).

- [ ] **Step 3: Implement**

Create `Sources/BabelOtterKit/Readiness/ReadinessPolicy.swift`:

```swift
import Foundation

/// How ready babelOtter is, at the granularity the menu bar shows (`FR-UI-03`).
///
/// Declared in increasing severity: the synthesised `Comparable` follows
/// declaration order, so the worst of several readinesses is their `max`.
public enum Readiness: Sendable, Equatable, Comparable, CaseIterable {
    case ready
    case degraded
    case blocked
}
```

In `Sources/BabelOtterKit/LLM/DaemonStatus.swift`, delete the `Readiness` enum and its doc comment (lines 9-14), and replace `readiness` and the comment above `canGenerate`:

```swift
    /// Nothing about the daemon is ever blocked. Blocked is reserved for a
    /// missing system permission -- something babelOtter cannot work without
    /// until the user changes a system setting. An unreachable daemon is
    /// usually just not started, and the menu names it.
    public var readiness: Readiness {
        switch self {
        case .ready: return .ready
        case .modelMissing, .unreachable: return .degraded
        }
    }

    /// Neither a missing model nor an unreachable daemon can generate, and
    /// they refuse differently: a missing model is one confirmation away from
    /// working, whereas an unreachable daemon needs the user to start it.
    public var canGenerate: Bool {
```

(The body of `canGenerate` is unchanged.)

In `Sources/BabelOtterKit/Config/Configuration.swift`, add to `Action` after `case repitch`:

```swift

    /// The name the menu and the readiness causes show.
    public var displayName: String {
        switch self {
        case .translate: return "Translate"
        case .correct: return "Correct"
        case .explain: return "Explain"
        case .repitch: return "Re-pitch"
        }
    }
```

In `.github/workflows/mutation.yml`, add to `PASS1` after the `Sources/BabelOtterKit/Privacy/UserText.swift` line, keeping its indentation:

```
          Sources/BabelOtterKit/Readiness/ReadinessPolicy.swift
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "ReadinessPolicyTests|DaemonStatusTests|OllamaClientTests"`
Expected: PASS.

Then run the whole suite: `swift test`
Expected: PASS (the architecture tests confirm ASCII and no UI imports).

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterKit/Readiness/ReadinessPolicy.swift Sources/BabelOtterKit/LLM/DaemonStatus.swift Sources/BabelOtterKit/Config/Configuration.swift Tests/BabelOtterKitTests/Readiness/ReadinessPolicyTests.swift Tests/BabelOtterKitTests/LLM/DaemonStatusTests.swift Tests/BabelOtterKitTests/LLM/OllamaClientTests.swift .github/workflows/mutation.yml
git commit -m "feat(readiness): order readiness by severity; an unreachable daemon is degraded

Blocked is reserved for a missing system permission (#29).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: One probe for the daemon

The monitor checks two models but must ask Ollama once. `probe()` exposes the single `/api/tags` request that `health` already makes.

**Files:**
- Modify: `Sources/BabelOtterKit/LLM/OllamaClient.swift:173-189`, `Tests/BabelOtterKitTests/LLM/OllamaClientTests.swift`

**Interfaces:**
- Consumes: `DaemonProbe` (existing, `DaemonStatus.swift`).
- Produces: `public func probe() async -> DaemonProbe` on `OllamaClient`.

- [ ] **Step 1: Write the failing tests**

Add to `OllamaClientTests` in `Tests/BabelOtterKitTests/LLM/OllamaClientTests.swift`, after `healthNeverThrows`:

```swift
    @Test("probe lists the installed models from a single tags request")
    func probeReachable() async throws {
        let transport = FakeTransport(chunks: [
            #"{"models":[{"name":"a","size":1},{"name":"b","size":2}]}"#
        ])
        let client = OllamaClient(endpoint: .loopback, transport: transport)
        #expect(await client.probe() == .reachable(models: ["a", "b"]))
        #expect(transport.requestedURLs.count == 1)
        #expect(try #require(transport.requestedURLs.first).path().hasSuffix("/api/tags"))
    }

    @Test("probe turns an unreachable daemon into a result, not a thrown error")
    func probeUnreachable() async {
        let transport = FakeTransport(
            chunks: [], failure: OllamaTransportError.unreachable(detail: "refused"))
        let client = OllamaClient(endpoint: .loopback, transport: transport)
        #expect(await client.probe() == .unreachable(detail: "refused"))
    }

    @Test("probe explains a bad HTTP status")
    func probeExplainsHTTPFailures() async {
        let transport = FakeTransport(chunks: [], failure: OllamaTransportError.httpStatus(503))
        let client = OllamaClient(endpoint: .loopback, transport: transport)
        #expect(await client.probe() == .unreachable(detail: "the daemon answered with HTTP 503"))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter OllamaClientTests`
Expected: build failure, `value of type 'OllamaClient' has no member 'probe'`.

- [ ] **Step 3: Implement**

In `Sources/BabelOtterKit/LLM/OllamaClient.swift`, replace `health(configuredModel:)` and its doc comment with:

```swift
    /// One request to the daemon: what it holds, or why it could not be asked.
    ///
    /// Deliberately non-throwing. #45 wants a health check that never blocks
    /// and never fails loudly -- it exists to tell the menu bar what to show,
    /// and a health check that can itself error just moves the problem. Every
    /// failure becomes a probe result the UI already knows how to render.
    public func probe() async -> DaemonProbe {
        do {
            return .reachable(models: try await installedModels().map(\.name))
        } catch let error as OllamaTransportError {
            return .unreachable(detail: Self.describe(error))
        } catch {
            return .unreachable(detail: error.localizedDescription)
        }
    }

    /// Whether the daemon is up and holds the model this action needs.
    public func health(configuredModel: String) async -> DaemonStatus {
        DaemonStatusPolicy().status(probe: await probe(), configuredModel: configuredModel)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter OllamaClientTests`
Expected: PASS, the existing `health*` tests included.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterKit/LLM/OllamaClient.swift Tests/BabelOtterKitTests/LLM/OllamaClientTests.swift
git commit -m "feat(ollama): expose one probe of the daemon

The readiness check covers two models with a single tags request.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The readiness policy

The rules from spec section 3.1: facts in, the worst readiness and the causes (worst first) out. Hotkey clashes are compared against the system shortcuts on four modifier bits.

**Files:**
- Modify: `Sources/BabelOtterKit/Readiness/ReadinessPolicy.swift`, `Tests/BabelOtterKitTests/Readiness/ReadinessPolicyTests.swift`, `docs/superpowers/specs/2026-10-06-readiness-design.md` (one detail string)

**Interfaces:**
- Consumes: `Readiness`, `Action.displayName` (Task 1); `DaemonProbe` (existing).
- Produces (all `public`, all `Sendable, Equatable`, each struct with a public memberwise `init` in field order):
  - `HotKeyCombination { keyCode: UInt32; modifiers: UInt32; displayName: String }`
  - `HotKeyFact { action: Action; combination: HotKeyCombination; registered: Bool }`
  - `SystemShortcut { keyCode: UInt32; modifiers: UInt32; enabled: Bool }`, with `static let comparedModifiers: UInt32` and `static func carbonModifiers(fromSymbolic value: Int) -> UInt32`
  - `ReadinessFacts { accessibilityGranted: Bool; probe: DaemonProbe; models: [Action: String]; hotKeys: [HotKeyFact]; systemShortcuts: [SystemShortcut] }`
  - `enum ReadinessCause { accessibilityMissing; ollamaUnreachable(detail: String); modelMissing(action: Action, model: String); hotKeyNotRegistered(action: Action, combination: String); hotKeyClashesWithSystem(action: Action, combination: String) }` with `readiness: Readiness` and `detail: String`
  - `ReadinessReport { readiness: Readiness; causes: [ReadinessCause] }` with `init(causes:)`
  - `ReadinessPolicy` with `init()` and `func report(for facts: ReadinessFacts) -> ReadinessReport`

- [ ] **Step 1: Write the failing tests**

Add to `ReadinessPolicyTests` (inside the struct, after `actionDisplayNames`):

```swift
    // MARK: - Policy

    private let policy = ReadinessPolicy()

    /// kVK_ANSI_T is 0x11, kVK_ANSI_C is 0x08; controlKey | optionKey is 0x1800.
    private static let controlOptionT = HotKeyCombination(
        keyCode: 0x11, modifiers: 0x1800, displayName: "Control-Option-T")
    private static let controlOptionC = HotKeyCombination(
        keyCode: 0x08, modifiers: 0x1800, displayName: "Control-Option-C")

    private static let bothRegistered = [
        HotKeyFact(action: .translate, combination: controlOptionT, registered: true),
        HotKeyFact(action: .correct, combination: controlOptionC, registered: true),
    ]

    private func facts(
        accessibility: Bool = true,
        probe: DaemonProbe = .reachable(models: ["m"]),
        models: [Action: String] = [.translate: "m", .correct: "m"],
        hotKeys: [HotKeyFact] = ReadinessPolicyTests.bothRegistered,
        systemShortcuts: [SystemShortcut] = []
    ) -> ReadinessFacts {
        ReadinessFacts(
            accessibilityGranted: accessibility, probe: probe, models: models,
            hotKeys: hotKeys, systemShortcuts: systemShortcuts)
    }

    @Test("everything in order is ready, with no causes")
    func allGood() {
        let report = policy.report(for: facts())
        #expect(report.readiness == .ready)
        #expect(report.causes.isEmpty)
    }

    @Test("a report with no causes is ready")
    func emptyReportIsReady() {
        #expect(ReadinessReport(causes: []).readiness == .ready)
    }

    @Test("missing Accessibility blocks, and says why")
    func accessibilityMissing() {
        let report = policy.report(for: facts(accessibility: false))
        #expect(report.readiness == .blocked)
        #expect(report.causes == [.accessibilityMissing])
        #expect(ReadinessCause.accessibilityMissing.detail
            == "Accessibility is not granted, so babelOtter can't read your selection.")
    }

    @Test("an unreachable daemon is one degraded cause, with no model causes")
    func ollamaUnreachable() {
        let report = policy.report(for: facts(
            probe: .unreachable(detail: "connection refused"),
            models: [.translate: "a", .correct: "b"]))
        #expect(report.readiness == .degraded)
        #expect(report.causes == [.ollamaUnreachable(detail: "connection refused")])
    }

    // Review focus 3: the daemon's own text is passed through untouched, with
    // no period of ours after it.
    @Test("the unreachable detail adds no punctuation after the daemon's text")
    func ollamaDetailExact() {
        #expect(ReadinessCause.ollamaUnreachable(detail: "connection refused.").detail
            == "Ollama is not reachable: connection refused.")
    }

    @Test("a missing model names the action and the model")
    func modelMissing() {
        let report = policy.report(for: facts(
            probe: .reachable(models: ["m"]),
            models: [.translate: "m", .correct: "other:7b"]))
        #expect(report.readiness == .degraded)
        #expect(report.causes == [.modelMissing(action: .correct, model: "other:7b")])
        #expect(report.causes[0].detail == "Correct: the model other:7b is not installed.")
    }

    @Test("two actions sharing a missing model are two causes, in action order")
    func sharedMissingModel() {
        let report = policy.report(for: facts(
            probe: .reachable(models: []),
            models: [.correct: "m", .translate: "m"]))
        #expect(report.causes == [
            .modelMissing(action: .translate, model: "m"),
            .modelMissing(action: .correct, model: "m"),
        ])
    }

    @Test("model matching is exact: another tag of the same model is missing")
    func tagMismatch() {
        let report = policy.report(for: facts(
            probe: .reachable(models: ["mistral-small3.2:latest"]),
            models: [.translate: "mistral-small3.2:24b"]))
        #expect(report.causes == [.modelMissing(action: .translate, model: "mistral-small3.2:24b")])
    }

    @Test("an action with no model listed is not checked")
    func unlistedActionNotChecked() {
        let report = policy.report(for: facts(probe: .reachable(models: []), models: [:]))
        #expect(report.causes.isEmpty)
    }

    @Test("an unregistered hotkey is degraded, and points at the menu")
    func hotKeyNotRegistered() {
        let report = policy.report(for: facts(hotKeys: [
            HotKeyFact(action: .translate, combination: Self.controlOptionT, registered: false)
        ]))
        #expect(report.readiness == .degraded)
        #expect(report.causes == [
            .hotKeyNotRegistered(action: .translate, combination: "Control-Option-T")
        ])
        #expect(report.causes[0].detail
            == "Control-Option-T couldn't be registered. Use the menu for Translate.")
    }

    @Test("a hotkey matching an enabled system shortcut clashes")
    func clashWithEnabledShortcut() {
        let report = policy.report(for: facts(systemShortcuts: [
            SystemShortcut(keyCode: 0x11, modifiers: 0x1800, enabled: true)
        ]))
        #expect(report.readiness == .degraded)
        #expect(report.causes == [
            .hotKeyClashesWithSystem(action: .translate, combination: "Control-Option-T")
        ])
        #expect(report.causes[0].detail
            == "Control-Option-T is also a system shortcut, so it may not reach Translate."
            + " Change it in System Settings \u{203A} Keyboard \u{203A} Keyboard Shortcuts,"
            + " or use the menu.")
    }

    @Test("a disabled system shortcut is no clash")
    func disabledShortcutNoClash() {
        let report = policy.report(for: facts(systemShortcuts: [
            SystemShortcut(keyCode: 0x11, modifiers: 0x1800, enabled: false)
        ]))
        #expect(report.causes.isEmpty)
    }

    @Test("the same key with other modifiers is no clash")
    func otherModifiersNoClash() {
        let report = policy.report(for: facts(systemShortcuts: [
            SystemShortcut(keyCode: 0x11, modifiers: 0x0900, enabled: true),
            SystemShortcut(keyCode: 0x11, modifiers: 0x1000, enabled: true),
        ]))
        #expect(report.causes.isEmpty)
    }

    @Test("the same modifiers on another key is no clash")
    func otherKeyNoClash() {
        let report = policy.report(for: facts(systemShortcuts: [
            SystemShortcut(keyCode: 0x12, modifiers: 0x1800, enabled: true)
        ]))
        #expect(report.causes.isEmpty)
    }

    @Test("only command, shift, option and control are compared")
    func onlyFourModifierBitsCompared() {
        let report = policy.report(for: facts(systemShortcuts: [
            SystemShortcut(keyCode: 0x11, modifiers: 0x1800 | 0x20000, enabled: true)
        ]))
        #expect(report.causes == [
            .hotKeyClashesWithSystem(action: .translate, combination: "Control-Option-T")
        ])
    }

    @Test("an unregistered hotkey that also clashes reports only the registration")
    func notRegisteredWinsOverClash() {
        let report = policy.report(for: facts(
            hotKeys: [HotKeyFact(action: .correct, combination: Self.controlOptionC, registered: false)],
            systemShortcuts: [SystemShortcut(keyCode: 0x08, modifiers: 0x1800, enabled: true)]))
        #expect(report.causes == [
            .hotKeyNotRegistered(action: .correct, combination: "Control-Option-C")
        ])
    }

    @Test("hotkey causes follow action order, whatever order the facts arrive in")
    func hotKeyCausesInActionOrder() {
        let report = policy.report(for: facts(hotKeys: [
            HotKeyFact(action: .correct, combination: Self.controlOptionC, registered: false),
            HotKeyFact(action: .translate, combination: Self.controlOptionT, registered: false),
        ]))
        #expect(report.causes == [
            .hotKeyNotRegistered(action: .translate, combination: "Control-Option-T"),
            .hotKeyNotRegistered(action: .correct, combination: "Control-Option-C"),
        ])
    }

    @Test("several causes: blocked wins, and the order is fixed")
    func severalCauses() {
        let report = policy.report(for: facts(
            accessibility: false,
            probe: .unreachable(detail: "refused"),
            hotKeys: [HotKeyFact(action: .translate, combination: Self.controlOptionT, registered: false)]))
        #expect(report.readiness == .blocked)
        #expect(report.causes == [
            .accessibilityMissing,
            .ollamaUnreachable(detail: "refused"),
            .hotKeyNotRegistered(action: .translate, combination: "Control-Option-T"),
        ])
    }

    @Test("model causes come before hotkey causes")
    func modelBeforeHotKey() {
        let report = policy.report(for: facts(
            probe: .reachable(models: []),
            models: [.correct: "m"],
            hotKeys: [HotKeyFact(action: .translate, combination: Self.controlOptionT, registered: false)]))
        #expect(report.causes == [
            .modelMissing(action: .correct, model: "m"),
            .hotKeyNotRegistered(action: .translate, combination: "Control-Option-T"),
        ])
    }

    @Test("each cause carries its own readiness")
    func causeReadiness() {
        #expect(ReadinessCause.accessibilityMissing.readiness == .blocked)
        #expect(ReadinessCause.ollamaUnreachable(detail: "d").readiness == .degraded)
        #expect(ReadinessCause.modelMissing(action: .translate, model: "m").readiness == .degraded)
        #expect(ReadinessCause.hotKeyNotRegistered(action: .translate, combination: "c").readiness
            == .degraded)
        #expect(ReadinessCause.hotKeyClashesWithSystem(action: .translate, combination: "c").readiness
            == .degraded)
    }

    @Test("recovery needs no restart: the next facts decide")
    func recovers() {
        #expect(policy.report(for: facts(accessibility: false)).readiness == .blocked)
        #expect(policy.report(for: facts()).readiness == .ready)
    }

    // Measured 2026-10-08 (spec section 3.4): CopySymbolicHotKeys reports Carbon
    // bits, with 0x20000 (kEventKeyModifierFnMask) on function and arrow keys.
    @Test("symbolic hotkey modifiers keep only the four compared Carbon bits")
    func carbonModifiersFromSymbolic() {
        #expect(SystemShortcut.carbonModifiers(fromSymbolic: 0x300) == 0x300)
        #expect(SystemShortcut.carbonModifiers(fromSymbolic: 0x21000) == 0x1000)
        #expect(SystemShortcut.carbonModifiers(fromSymbolic: 0x1B00) == 0x1B00)
        #expect(SystemShortcut.carbonModifiers(fromSymbolic: 0x20000) == 0)
        #expect(SystemShortcut.carbonModifiers(fromSymbolic: 0x400) == 0)
        #expect(SystemShortcut.comparedModifiers == 0x1B00)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter ReadinessPolicyTests`
Expected: build failure, `cannot find 'ReadinessPolicy' in scope` (and the other new types).

- [ ] **Step 3: Implement**

Append to `Sources/BabelOtterKit/Readiness/ReadinessPolicy.swift`:

```swift

/// A hotkey as registered: Carbon key code and modifier bits, and the name
/// the menu shows.
public struct HotKeyCombination: Sendable, Equatable {
    public let keyCode: UInt32
    /// Carbon modifier bits (`cmdKey`, `shiftKey`, `optionKey`, `controlKey`).
    public let modifiers: UInt32
    /// "Control-Option-T".
    public let displayName: String

    public init(keyCode: UInt32, modifiers: UInt32, displayName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayName = displayName
    }
}

/// One action's hotkey, and whether `RegisterEventHotKey` accepted it.
public struct HotKeyFact: Sendable, Equatable {
    public let action: Action
    public let combination: HotKeyCombination
    public let registered: Bool

    public init(action: Action, combination: HotKeyCombination, registered: Bool) {
        self.action = action
        self.combination = combination
        self.registered = registered
    }
}

/// One system-wide shortcut from System Settings > Keyboard > Keyboard
/// Shortcuts, as `CopySymbolicHotKeys` reports it.
public struct SystemShortcut: Sendable, Equatable {
    public let keyCode: UInt32
    /// Carbon modifier bits, already passed through `carbonModifiers(fromSymbolic:)`.
    public let modifiers: UInt32
    public let enabled: Bool

    public init(keyCode: UInt32, modifiers: UInt32, enabled: Bool) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.enabled = enabled
    }

    /// Carbon's `cmdKey | shiftKey | optionKey | controlKey`. Written as
    /// literals because the kit cannot import Carbon (`NoUIImportsTests`).
    public static let comparedModifiers: UInt32 = 0x100 | 0x200 | 0x800 | 0x1000

    /// `CopySymbolicHotKeys` reports modifiers as Carbon bits. Measured
    /// 2026-10-08 on macOS 26: Command-Shift-3 is key code 20 with 0x300, and
    /// function and arrow keys add 0x20000 (`kEventKeyModifierFnMask`). Only
    /// the four compared bits are kept.
    public static func carbonModifiers(fromSymbolic value: Int) -> UInt32 {
        UInt32(truncatingIfNeeded: value) & comparedModifiers
    }
}

/// Everything readiness is decided from, gathered by the app.
public struct ReadinessFacts: Sendable, Equatable {
    public let accessibilityGranted: Bool
    public let probe: DaemonProbe
    /// The model for each action being checked. An action not listed is not
    /// checked.
    public let models: [Action: String]
    public let hotKeys: [HotKeyFact]
    public let systemShortcuts: [SystemShortcut]

    public init(
        accessibilityGranted: Bool, probe: DaemonProbe, models: [Action: String],
        hotKeys: [HotKeyFact], systemShortcuts: [SystemShortcut]
    ) {
        self.accessibilityGranted = accessibilityGranted
        self.probe = probe
        self.models = models
        self.hotKeys = hotKeys
        self.systemShortcuts = systemShortcuts
    }
}

/// One reason babelOtter is not fully ready, worded for a menu line.
public enum ReadinessCause: Sendable, Equatable {
    case accessibilityMissing
    case ollamaUnreachable(detail: String)
    case modelMissing(action: Action, model: String)
    case hotKeyNotRegistered(action: Action, combination: String)
    case hotKeyClashesWithSystem(action: Action, combination: String)

    /// Blocked only for a missing system permission; everything else leaves
    /// some of babelOtter working.
    public var readiness: Readiness {
        switch self {
        case .accessibilityMissing:
            return .blocked
        case .ollamaUnreachable, .modelMissing, .hotKeyNotRegistered, .hotKeyClashesWithSystem:
            return .degraded
        }
    }

    public var detail: String {
        switch self {
        case .accessibilityMissing:
            return "Accessibility is not granted, so babelOtter can't read your selection."
        case .ollamaUnreachable(let detail):
            // No period of ours: the daemon's text may already end in one.
            return "Ollama is not reachable: \(detail)"
        case .modelMissing(let action, let model):
            return "\(action.displayName): the model \(model) is not installed."
        case .hotKeyNotRegistered(let action, let combination):
            return "\(combination) couldn't be registered. Use the menu for \(action.displayName)."
        case .hotKeyClashesWithSystem(let action, let combination):
            return "\(combination) is also a system shortcut, so it may not reach \(action.displayName)."
                + " Change it in System Settings \u{203A} Keyboard \u{203A} Keyboard Shortcuts,"
                + " or use the menu."
        }
    }
}

/// The worst readiness and every cause, worst first.
public struct ReadinessReport: Sendable, Equatable {
    public let readiness: Readiness
    public let causes: [ReadinessCause]

    public init(causes: [ReadinessCause]) {
        self.causes = causes
        var worst = Readiness.ready
        for cause in causes {
            worst = max(worst, cause.readiness)
        }
        self.readiness = worst
    }
}

/// Turns facts into a report (`FR-UI-03`, `FR-ONB-02`).
///
/// Like `DaemonStatusPolicy`, it holds no state: every report is computed
/// from the facts in front of it, so recovery needs no restart.
///
/// Written as loops over named functions rather than closures: muter drops
/// mutants inside closures and reports them as survivors.
public struct ReadinessPolicy: Sendable {

    public init() {}

    /// Order: Accessibility, then the daemon, then each action's model, then
    /// each action's hotkey. The only blocked cause comes first.
    public func report(for facts: ReadinessFacts) -> ReadinessReport {
        var causes: [ReadinessCause] = []
        if !facts.accessibilityGranted {
            causes += [.accessibilityMissing]
        }
        causes += daemonCauses(facts)
        for action in Action.allCases {
            if let cause = hotKeyCause(for: action, in: facts) {
                causes += [cause]
            }
        }
        return ReadinessReport(causes: causes)
    }

    /// One cause for an unreachable daemon, however many actions are checked:
    /// whether a model is installed cannot be known then.
    private func daemonCauses(_ facts: ReadinessFacts) -> [ReadinessCause] {
        switch facts.probe {
        case .unreachable(let detail):
            return [.ollamaUnreachable(detail: detail)]
        case .reachable(let installed):
            var causes: [ReadinessCause] = []
            for action in Action.allCases {
                if let cause = modelCause(for: action, models: facts.models, installed: installed) {
                    causes += [cause]
                }
            }
            return causes
        }
    }

    /// Exact match, tag included, as in `DaemonStatusPolicy`.
    private func modelCause(
        for action: Action, models: [Action: String], installed: [String]
    ) -> ReadinessCause? {
        guard let model = models[action] else { return nil }
        if installed.contains(model) { return nil }
        return .modelMissing(action: action, model: model)
    }

    /// At most one cause per action. An unregistered hotkey cannot clash, so
    /// that is the one reported.
    private func hotKeyCause(for action: Action, in facts: ReadinessFacts) -> ReadinessCause? {
        guard let fact = firstHotKey(for: action, in: facts.hotKeys) else { return nil }
        let name = fact.combination.displayName
        if !fact.registered {
            return .hotKeyNotRegistered(action: action, combination: name)
        }
        if clashes(fact.combination, with: facts.systemShortcuts) {
            return .hotKeyClashesWithSystem(action: action, combination: name)
        }
        return nil
    }

    private func firstHotKey(for action: Action, in hotKeys: [HotKeyFact]) -> HotKeyFact? {
        for fact in hotKeys where fact.action == action {
            return fact
        }
        return nil
    }

    private func clashes(_ combination: HotKeyCombination, with shortcuts: [SystemShortcut]) -> Bool {
        let ours = combination.modifiers & SystemShortcut.comparedModifiers
        for shortcut in shortcuts where shortcut.enabled {
            let theirs = shortcut.modifiers & SystemShortcut.comparedModifiers
            if shortcut.keyCode == combination.keyCode && theirs == ours {
                return true
            }
        }
        return false
    }
}
```

In `docs/superpowers/specs/2026-10-06-readiness-design.md`, section 3.1's details table, change the `ollamaUnreachable` row's detail from `"Ollama is not reachable: `d`."` to `"Ollama is not reachable: `d`"`, and add below the table: "No period follows the daemon's text, which may already end in one."

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ReadinessPolicyTests`
Expected: PASS.

Then: `swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterKit/Readiness/ReadinessPolicy.swift Tests/BabelOtterKitTests/Readiness/ReadinessPolicyTests.swift docs/superpowers/specs/2026-10-06-readiness-design.md
git commit -m "feat(readiness): decide readiness and its causes from the facts

Accessibility missing blocks; the daemon, a missing model, an
unregistered hotkey and a clash with a system shortcut degrade (#28, #29).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The monitor, the icon and the menu

The app gathers the facts, runs the policy and draws the result. The hotkey messages stop writing into the Ollama line (the #26 bug), because that line no longer exists.

**Files:**
- Create: `Sources/BabelOtterApp/ReadinessMonitor.swift`
- Modify: `Sources/BabelOtterApp/AppDelegate.swift`

**Interfaces:**
- Consumes: everything Task 3 produces; `OllamaClient.probe()` (Task 2); `AppEnvironment` (existing).
- Produces:
  - `@MainActor final class ReadinessMonitor` with `init(environment: AppEnvironment)`, `var hotKeys: [HotKeyFact]`, `var onChange: (@MainActor (ReadinessReport) -> Void)?`, `private(set) var report: ReadinessReport?`, `func start()`, `func refresh()`
  - `enum AccessibilitySettings { @MainActor static func open() }`
  - `AppDelegate.monitor` (private), used by Task 5.

- [ ] **Step 1: Create the monitor**

Create `Sources/BabelOtterApp/ReadinessMonitor.swift`:

```swift
import AppKit
import ApplicationServices
import BabelOtterKit
import Carbon.HIToolbox

/// Gathers the readiness facts and runs `ReadinessPolicy` over them.
///
/// Checks on a 30 s loop and on wake by itself; `AppDelegate` also asks for a
/// check when the menu opens and when an action is triggered. A check already
/// running is joined, not duplicated, so a slow daemon never stacks probes.
@MainActor
final class ReadinessMonitor {

    /// nil until the first check finishes.
    private(set) var report: ReadinessReport?
    /// Set once by `AppDelegate`, after registering the hotkeys.
    var hotKeys: [HotKeyFact] = []
    var onChange: (@MainActor (ReadinessReport) -> Void)?

    private let client: OllamaClient
    private let models: [Action: String]
    private var inFlight: Task<Void, Never>?
    private var loop: Task<Void, Never>?
    private var wakeObserver: (any NSObjectProtocol)?

    private static let interval = Duration.seconds(30)

    /// Only the actions that exist are checked. One without a configured
    /// model falls back to the default, as the pipeline does.
    init(environment: AppEnvironment) {
        client = environment.client
        var models: [Action: String] = [:]
        for action in [Action.translate, .correct] {
            models[action] = environment.configuration.models[action] ?? Configuration.defaultModel
        }
        self.models = models
    }

    func start() {
        refresh()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                self?.refresh()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        guard inFlight == nil else { return }
        inFlight = Task { [weak self] in
            await self?.check()
        }
    }

    private func check() async {
        let granted = AXIsProcessTrusted()
        let probe = await client.probe()
        let facts = ReadinessFacts(
            accessibilityGranted: granted, probe: probe, models: models,
            hotKeys: hotKeys, systemShortcuts: Self.systemShortcuts())
        let report = ReadinessPolicy().report(for: facts)
        self.report = report
        inFlight = nil
        onChange?(report)
    }

    /// Read on every check, so a shortcut changed in System Settings shows up
    /// without a relaunch.
    private static func systemShortcuts() -> [SystemShortcut] {
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == noErr,
            let entries = array?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        var shortcuts: [SystemShortcut] = []
        for entry in entries {
            guard let code = entry[kHISymbolicHotKeyCode as String] as? Int,
                let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int
            else { continue }
            let enabled = entry[kHISymbolicHotKeyEnabled as String] as? Bool ?? false
            shortcuts += [
                SystemShortcut(
                    keyCode: UInt32(truncatingIfNeeded: code),
                    modifiers: SystemShortcut.carbonModifiers(fromSymbolic: modifiers),
                    enabled: enabled)
            ]
        }
        return shortcuts
    }
}

/// Privacy & Security > Accessibility, where the grant is made.
enum AccessibilitySettings {
    @MainActor static func open() {
        let address = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 2: Wire `AppDelegate`**

In `Sources/BabelOtterApp/AppDelegate.swift`:

1. Conform to `NSMenuDelegate`: `final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {`.
2. Delete the `ollamaLine` and `accessLine` properties. Add, below `configLine`:

```swift
    /// The readiness lines: a headline, one line per cause, and "Open
    /// Accessibility Settings..." when that is a cause. Replaced as a block on
    /// every report, in place, so an open menu updates too.
    private var statusLines: [NSMenuItem] = []
```

3. Below `environment`, add:

```swift
    private lazy var monitor = ReadinessMonitor(environment: environment)

    private static let translateCombination = HotKeyCombination(
        keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey),
        displayName: "Control-Option-T")
    private static let correctCombination = HotKeyCombination(
        keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey),
        displayName: "Control-Option-C")
```

4. Replace `applicationDidFinishLaunching(_:)` with:

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        registerHotKeys()
        promptForAccessibilityIfNeeded()
        monitor.onChange = { [weak self] report in self?.render(report) }
        render(nil)
        monitor.start()
    }

    /// Registration stays non-exclusive. A failure is recorded as a fact and
    /// reaches the menu as a cause, never written over another line (#26).
    private func registerHotKeys() {
        let translate = Self.translateCombination
        hotKey = HotKey(keyCode: translate.keyCode, modifiers: translate.modifiers, id: 1) {
            [weak self] in self?.startAction(.translate)
        }
        let correct = Self.correctCombination
        correctHotKey = HotKey(keyCode: correct.keyCode, modifiers: correct.modifiers, id: 2) {
            [weak self] in self?.startAction(.correct)
        }
        monitor.hotKeys = [
            HotKeyFact(action: .translate, combination: translate, registered: hotKey != nil),
            HotKeyFact(action: .correct, combination: correct, registered: correctHotKey != nil),
        ]
    }
```

5. In `buildMenu()`, set the delegate and drop the two old lines. The menu becomes:

```swift
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(action(
            "Translate Selection (\(Self.translateCombination.displayName))",
            #selector(translateSelectionAction)))
        menu.addItem(action(
            "Correct Selection (\(Self.correctCombination.displayName))",
            #selector(correctSelectionAction)))
        menu.addItem(configLine)
        menu.addItem(.separator())
        menu.addItem(action("Check Again", #selector(refreshStatusAction)))
        menu.addItem(action("Open Configuration Folder", #selector(openConfiguration)))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit babelOtter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
```

(The status lines are inserted just above `configLine` by `renderMenu`.)

6. Replace `refreshStatusAction()` and delete `refreshStatus()`:

```swift
    @objc private func refreshStatusAction() { monitor.refresh() }

    @objc private func openAccessibilitySettings() { AccessibilitySettings.open() }

    func menuWillOpen(_ menu: NSMenu) { monitor.refresh() }

    // MARK: - Readiness

    private func render(_ report: ReadinessReport?) {
        renderIcon(report)
        renderMenu(report)
    }

    private func renderIcon(_ report: ReadinessReport?) {
        guard let button = statusItem?.button else { return }
        let symbol: String?
        switch report?.readiness {
        case .degraded: symbol = "exclamationmark.triangle"
        case .blocked: symbol = "xmark.octagon.fill"
        case .ready, nil: symbol = nil
        }
        let image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageTrailing
        let label = Self.iconLabel(report)
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    private static func iconLabel(_ report: ReadinessReport?) -> String {
        guard let report else { return "babelOtter: checking" }
        guard let first = report.causes.first else { return "babelOtter: ready" }
        return "babelOtter: \(headline(report).lowercased()). \(first.detail)"
    }

    private static func headline(_ report: ReadinessReport?) -> String {
        guard let report else { return "Checking..." }
        switch report.readiness {
        case .ready: return "Ready"
        case .degraded: return "Degraded"
        case .blocked: return "Blocked"
        }
    }

    private func renderMenu(_ report: ReadinessReport?) {
        guard let menu = statusItem?.menu else { return }
        for item in statusLines { menu.removeItem(item) }
        statusLines = makeStatusLines(report)
        var index = menu.index(of: configLine)
        for item in statusLines {
            menu.insertItem(item, at: index)
            index += 1
        }
    }

    private func makeStatusLines(_ report: ReadinessReport?) -> [NSMenuItem] {
        var lines = [NSMenuItem(title: Self.headline(report), action: nil, keyEquivalent: "")]
        for cause in report?.causes ?? [] {
            lines.append(NSMenuItem(title: cause.detail, action: nil, keyEquivalent: ""))
        }
        if report?.causes.contains(.accessibilityMissing) == true {
            lines.append(action("Open Accessibility Settings\u{2026}", #selector(openAccessibilitySettings)))
        }
        return lines
    }
```

7. At the top of `startAction(_:)`, before the `AXIsProcessTrusted()` guard, add:

```swift
        monitor.refresh()
```

- [ ] **Step 3: Build**

Run: `swift build --product BabelOtterApp -Xswiftc -warnings-as-errors`
Expected: `Build complete!` with no warnings. Fix any Swift 6 isolation error in place, keeping the shape above.

Run: `swift test`
Expected: PASS (`NetworkingCallSiteTests` scans the new app file).

- [ ] **Step 4: Assemble, launch, quit**

Run: `Tools/make-app.sh --run`
Expected: `built build/babelOtter.app`; the otter appears in the menu bar. Open the menu: a "Ready" (or a named cause) headline sits above the configuration line, and no "Ollama:" or "Accessibility:" line remains. Quit from the menu.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterApp/ReadinessMonitor.swift Sources/BabelOtterApp/AppDelegate.swift
git commit -m "feat(app): show readiness in the menu bar icon and name each cause

Checks every 30 s and on menu open, action and wake. A failed hotkey is
now its own cause line instead of being overwritten by the Ollama
status (#26, #29).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Explain a missing permission in the popup

An action without Accessibility opens the popup with an explanation and a button to the right System Settings pane, instead of re-asking the system prompt. The system prompt runs at first launch only.

**Files:**
- Modify: `Sources/BabelOtterApp/PopupModel.swift`, `Sources/BabelOtterApp/PopupView.swift`, `Sources/BabelOtterApp/AppDelegate.swift`

**Interfaces:**
- Consumes: `AccessibilitySettings.open()`, `AppDelegate.monitor` (Task 4).
- Produces: `PopupModel.Phase.needsAccessibility`, `PopupModel.requireAccessibility()`, `PopupModel.openAccessibilitySettings()`.

- [ ] **Step 1: The popup model**

In `Sources/BabelOtterApp/PopupModel.swift`:

1. Add a case to `Phase`, after `case failed(String)`:

```swift
        /// Accessibility is not granted, so nothing was captured.
        case needsAccessibility
```

2. In `canRegenerate`, change `case .capturing, .choosingDirection: return false` to:

```swift
        case .capturing, .choosingDirection, .needsAccessibility: return false
```

3. Add after `displayName(_:)`:

```swift
    /// Shown instead of a capture when Accessibility is not granted (#28).
    func requireAccessibility() {
        guard !isDismissed else { return }
        phase = .needsAccessibility
    }

    func openAccessibilitySettings() {
        AccessibilitySettings.open()
        dismiss()
    }
```

- [ ] **Step 2: The popup view**

In `Sources/BabelOtterApp/PopupView.swift`:

1. In `content`, add a case to the `switch model.phase`, after `.failed`:

```swift
        case .needsAccessibility:
            Text("babelOtter needs Accessibility permission to read your selection.")
            Text("Turn it on for babelOtter in System Settings, then try again.")
                .font(.caption).foregroundStyle(.secondary)
```

2. Replace `actions` with:

```swift
    @ViewBuilder private var actions: some View {
        if model.phase == .needsAccessibility {
            HStack {
                Button("Open System Settings") { model.openAccessibilitySettings() }
                    .keyboardShortcut(.defaultAction)
                Spacer()
                Button("Dismiss") { model.dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        } else {
            resultActions
        }
    }

    private var resultActions: some View {
```

followed by the old body of `actions` unchanged (the `HStack` with Replace, Copy and Dismiss, and its comments).

- [ ] **Step 3: `AppDelegate`**

In `Sources/BabelOtterApp/AppDelegate.swift`:

1. Replace `promptForAccessibilityIfNeeded()` and its comment with:

```swift
    /// The system prompt, at first launch only. Afterwards a missing grant is
    /// explained in the popup and the menu, never by a dialog (#28).
    private func promptForAccessibilityIfNeeded() {
        let key = "promptedForAccessibility"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard !AXIsProcessTrusted() else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
```

2. In `startAction(_:)`, replace

```swift
        guard AXIsProcessTrusted() else {
            promptForAccessibilityIfNeeded()
            return
        }
        guard !isCapturing, currentModel?.isReplacing != true else { return }
```

with

```swift
        guard !isCapturing, currentModel?.isReplacing != true else { return }
        guard AXIsProcessTrusted() else {
            showAccessibilityNeeded(for: action)
            return
        }
```

(`monitor.refresh()` from Task 4 stays the first line, so the icon changes at the same moment.)

3. Add after `startAction(_:)`:

```swift
    /// No capture starts, so the panel may take focus at once: Return opens
    /// System Settings, Escape dismisses. A second press replaces this popup
    /// rather than stacking another.
    private func showAccessibilityNeeded(for action: Action) {
        currentModel?.dismiss()
        let model = PopupModel(
            action: action,
            environment: environment,
            close: { [weak self] in self?.panel.dismiss() },
            reopen: { [weak self] model in
                guard let self else { return }
                self.currentModel = model
                self.panel.show(PopupView(model: model))
            })
        model.requireAccessibility()
        currentModel = model
        panel.show(PopupView(model: model))
    }
```

- [ ] **Step 4: Build, assemble, launch, quit**

Run: `swift build --product BabelOtterApp -Xswiftc -warnings-as-errors`
Expected: `Build complete!` with no warnings.

Run: `swift test`
Expected: PASS.

Run: `Tools/make-app.sh --run`, then quit from the menu.
Expected: the app launches; with Accessibility granted, no dialog appears.

- [ ] **Step 5: Commit**

```bash
git add Sources/BabelOtterApp/PopupModel.swift Sources/BabelOtterApp/PopupView.swift Sources/BabelOtterApp/AppDelegate.swift
git commit -m "feat(app): explain a missing Accessibility grant in the popup

The popup links straight to the Accessibility pane; the system prompt
runs at first launch only (#28).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Hand over

**Files:**
- Modify: `docs/HANDOFF.md`

- [ ] **Step 1: Add an update to `docs/HANDOFF.md`**

Insert directly below the `# Handoff — state as of ...` heading (change its date to the day this lands), above the 2026-10-05 update:

```markdown
## Update <date>: readiness is built (#28, #29, the #26 bug)

The menu bar icon shows readiness: the otter alone is ready, a triangle is degraded, a stop sign is blocked. The menu names each cause above the configuration line. Blocked means only that Accessibility is missing; Ollama unreachable, a missing model, an unregistered hotkey and a hotkey clashing with a system shortcut are degraded. Checks run every 30 s and on menu open, action trigger and wake. An action without Accessibility opens the popup with **Open System Settings**; the system prompt runs at first launch only.

Spec: `docs/superpowers/specs/2026-10-06-readiness-design.md`. Plan: `docs/superpowers/plans/2026-10-08-readiness.md`.

**Measured 2026-10-08:** `CopySymbolicHotKeys` reports Carbon modifier bits (Command-Shift-3 is key code 20, `0x300`); function and arrow keys add `0x20000`. Carbon hotkeys are non-exclusive, so registration never fails because another app holds the combination, and no API lists other apps' hotkeys.

**Manual checks (yours):**

| # | Do | Expect |
|---|---|---|
| M1 | Revoke Accessibility for babelOtter in System Settings | Within 30 s: stop sign; menu reads "Blocked" and names Accessibility, with "Open Accessibility Settings…" |
| M2 | With it revoked, press Control-Option-T in any app | Popup explains; Return or the button opens the Accessibility pane and closes the popup; Escape dismisses |
| M3 | Grant it again | Within 30 s: the otter alone, "Ready"; no dialog |
| M4 | Stop Ollama (`pkill ollama` or quit the app) | Within 30 s: triangle; "Ollama is not reachable: ..." Start it: ready again |
| M5 | Set `models.correct` in `config.json` to a model that is not installed, relaunch | Triangle; "Correct: the model ... is not installed." Restore it |
| M6 | Pause Ollama (`pkill -STOP ollama`), wait 90 s, open the menu, then `pkill -CONT ollama` | No hang and no pile-up: the menu opens at once, and the status updates once the probe times out or Ollama resumes |
| M7 | Keep the menu open across a status change (open it, then stop Ollama and click Check Again) | The lines change in place; no duplicated headline or cause |
| M8 | Remove the `correct` entry from `models` in `config.json`, relaunch | Ready (the default model is checked, not skipped), assuming it is installed |
| M9 | With Accessibility revoked, press Control-Option-T three times quickly | One popup, replaced each time; nothing is captured |
| M10 | In System Settings › Keyboard › Keyboard Shortcuts, assign Control-Option-T to a Screenshots entry | Within 30 s: triangle; "Control-Option-T is also a system shortcut, so it may not reach Translate. ..." Press it and note which one fires; record that in `docs/architecture.md` section 7. Restore the shortcut: ready again |
```

- [ ] **Step 2: Commit**

```bash
git add docs/HANDOFF.md
git commit -m "docs: hand over readiness, with its manual checks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
