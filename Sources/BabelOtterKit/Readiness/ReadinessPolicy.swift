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
        case .hotKeyClashesWithSystem(_, let combination):
            // Measured: neither hotkey consumes the press, so both actions run
            // (docs/architecture.md section 7).
            return "\(combination) is also a system shortcut, so pressing it runs both."
                + " Change it in System Settings \u{203A} Keyboard \u{203A} Keyboard Shortcuts."
        }
    }
}

extension ReadinessCause {

    /// The cause in a few words, as the header of its menu section. The full
    /// `detail` stays in the icon's tooltip.
    public var header: String {
        switch self {
        case .accessibilityMissing:
            return "Accessibility isn't granted"
        case .ollamaUnreachable:
            return "Ollama isn't running"
        case .modelMissing(let action, let model):
            return "\(action.displayName): \(model) isn't installed"
        case .hotKeyNotRegistered(_, let combination):
            return "\(combination) is unavailable: use the menu"
        case .hotKeyClashesWithSystem(_, let combination):
            return "\(combination) is also a system shortcut"
        }
    }

    /// The menu command under the header. Nil when nothing outside the menu
    /// fixes it: a hotkey that never registered is worked round by the
    /// menu's own action item.
    public var remedy: ReadinessRemedy? {
        switch self {
        case .accessibilityMissing:
            return .openAccessibilitySettings
        case .ollamaUnreachable:
            return .startOllama
        case .modelMissing(_, let model):
            return .copyPullCommand("ollama pull \(model)")
        case .hotKeyNotRegistered:
            return nil
        case .hotKeyClashesWithSystem:
            return .openKeyboardShortcutsSettings
        }
    }
}

/// What the menu offers to fix a cause. The app carries each one out.
public enum ReadinessRemedy: Sendable, Equatable {
    case openAccessibilitySettings
    case startOllama
    /// The command to paste into a terminal.
    case copyPullCommand(String)
    case openKeyboardShortcutsSettings

    public var title: String {
        switch self {
        case .openAccessibilitySettings:
            return "Open Accessibility Settings\u{2026}"
        case .startOllama:
            return "Start Ollama"
        case .copyPullCommand(let command):
            return "Copy \u{201C}\(command)\u{201D}"
        case .openKeyboardShortcutsSettings:
            return "Open Keyboard Shortcuts Settings\u{2026}"
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
