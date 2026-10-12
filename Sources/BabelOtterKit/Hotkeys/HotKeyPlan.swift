import Foundation

/// A hotkey from config.json that is not used as written.
public struct HotKeyIssue: Sendable, Equatable {
    public let action: Action
    /// As written in the file.
    public let text: String
    public let problem: HotKeyProblem

    public init(action: Action, text: String, problem: HotKeyProblem) {
        self.action = action
        self.text = text
        self.problem = problem
    }

    /// `translate hotkey "contrl+option+T": unknown key or modifier "contrl"`,
    /// shown after "config.json: " in the menu.
    public var description: String {
        "\(action.rawValue) hotkey \"\(text)\": \(problem.detail)"
    }
}

/// Which combination each action gets, decided from the file, what is in
/// use, and the keyboard layout (#26).
///
/// A hotkey that cannot be used as written keeps the one in use, so a typo
/// never takes a working hotkey away. Written as loops and switches rather
/// than closures: muter drops mutants inside closures.
public struct HotKeyPlan: Sendable, Equatable {
    /// An action absent here has no hotkey.
    public let combinations: [Action: HotKeyCombination]
    public let issues: [HotKeyIssue]

    /// The actions with hotkeys, in the order they are decided: Translate
    /// first, so it wins a duplicate.
    public static let actions: [Action] = [.translate, .correct]

    /// What babelOtter registered before #26, and what is in use before the
    /// first plan: kVK_ANSI_T and kVK_ANSI_C with controlKey | optionKey.
    public static let launchCombinations: [Action: HotKeyCombination] = [
        .translate: HotKeyCombination(keyCode: 0x11, modifiers: 0x1800, displayName: "Control-Option-T"),
        .correct: HotKeyCombination(keyCode: 0x08, modifiers: 0x1800, displayName: "Control-Option-C"),
    ]

    public static func make(
        bindings: HotKeyBindings?, previous: [Action: HotKeyCombination], layout: KeyLayout
    ) -> HotKeyPlan {
        let written = bindings ?? HotKeyBindings()
        var combinations: [Action: HotKeyCombination] = [:]
        var issues: [HotKeyIssue] = []
        for action in actions {
            guard let text = text(for: written.binding(for: action), action: action) else {
                continue
            }
            switch resolve(text, layout: layout) {
            case .success(let combination):
                if let owner = owner(of: combination, in: combinations) {
                    issues += [HotKeyIssue(action: action, text: text, problem: .sharedWith(owner))]
                    if let taker = keepPrevious(for: action, from: previous, into: &combinations) {
                        issues += [HotKeyIssue(action: action, text: text, problem: .previousTakenBy(taker))]
                    }
                } else {
                    combinations[action] = combination
                }
            case .failure(let problem):
                issues += [HotKeyIssue(action: action, text: text, problem: problem)]
                if let taker = keepPrevious(for: action, from: previous, into: &combinations) {
                    issues += [HotKeyIssue(action: action, text: text, problem: .previousTakenBy(taker))]
                }
            }
        }
        return HotKeyPlan(combinations: combinations, issues: issues)
    }

    /// Nil when the hotkey is off.
    private static func text(for binding: HotKeyBinding, action: Action) -> String? {
        switch binding {
        case .off:
            return nil
        case .useDefault:
            return HotKeyBindings.defaultText(for: action)
        case .text(let text):
            return text
        }
    }

    private static func resolve(_ text: String, layout: KeyLayout) -> Result<HotKeyCombination, HotKeyProblem> {
        switch HotKeySpec.parse(text) {
        case .success(let spec):
            return layout.resolve(spec)
        case .failure(let problem):
            return .failure(problem)
        }
    }

    private static func owner(
        of combination: HotKeyCombination, in combinations: [Action: HotKeyCombination]
    ) -> Action? {
        for action in actions {
            if let taken = combinations[action] {
                if taken.sameKeys(as: combination) {
                    return action
                }
            }
        }
        return nil
    }

    /// The previous combination, unless another action now holds it.
    /// Returns that action when it does, so losing the hotkey is reported
    /// rather than left to the menu title to reveal.
    private static func keepPrevious(
        for action: Action, from previous: [Action: HotKeyCombination],
        into combinations: inout [Action: HotKeyCombination]
    ) -> Action? {
        guard let kept = previous[action] else { return nil }
        if let taker = owner(of: kept, in: combinations) {
            return taker
        }
        combinations[action] = kept
        return nil
    }
}
