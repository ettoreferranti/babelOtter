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
            == "Control-Option-T is also a system shortcut, so pressing it runs both."
            + " Change it in System Settings \u{203A} Keyboard \u{203A} Keyboard Shortcuts.")
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

    // MARK: - Menu: a short header per cause, and the command that fixes it

    @Test("each cause has a short header for its menu section")
    func headers() {
        #expect(ReadinessCause.accessibilityMissing.header == "Accessibility isn't granted")
        #expect(ReadinessCause.ollamaUnreachable(detail: "refused").header == "Ollama isn't running")
        #expect(ReadinessCause.modelMissing(action: .correct, model: "m:1b").header
            == "Correct: m:1b isn't installed")
        #expect(ReadinessCause.hotKeyNotRegistered(action: .translate, combination: "Control-Option-T")
            .header == "Control-Option-T is unavailable: use the menu")
        #expect(ReadinessCause.hotKeyClashesWithSystem(action: .translate, combination: "Control-Option-T")
            .header == "Control-Option-T is also a system shortcut")
    }

    @Test("each cause offers the command that fixes it, where there is one")
    func remedies() {
        #expect(ReadinessCause.accessibilityMissing.remedy == .openAccessibilitySettings)
        #expect(ReadinessCause.ollamaUnreachable(detail: "refused").remedy == .startOllama)
        #expect(ReadinessCause.modelMissing(action: .correct, model: "m:1b").remedy
            == .copyPullCommand("ollama pull m:1b"))
        #expect(ReadinessCause.hotKeyClashesWithSystem(action: .translate, combination: "C").remedy
            == .openKeyboardShortcutsSettings)
        // The menu's own Translate item is the way round a hotkey that never
        // registered; no setting fixes it.
        #expect(ReadinessCause.hotKeyNotRegistered(action: .translate, combination: "C").remedy == nil)
    }

    @Test("each remedy is titled as a menu command")
    func remedyTitles() {
        #expect(ReadinessRemedy.openAccessibilitySettings.title == "Open Accessibility Settings\u{2026}")
        #expect(ReadinessRemedy.startOllama.title == "Start Ollama")
        #expect(ReadinessRemedy.copyPullCommand("ollama pull m:1b").title
            == "Copy \u{201C}ollama pull m:1b\u{201D}")
        #expect(ReadinessRemedy.openKeyboardShortcutsSettings.title == "Open Keyboard Shortcuts Settings\u{2026}")
    }
}
