import Foundation

/// The quiet line under a translation (#136): write it yourself next
/// time, or read it with Explain. At most one a day.
public enum TranslateHint: Sendable, Equatable {
    /// Translated from my language: next time write it in the target.
    case write(LanguageCode)
    /// Translated into my language: Explain shows how the text works.
    case explain

    /// Shorter texts get no hint.
    public static let minimumWords = 5

    /// The hint for a finished translation; nil for a short text, when
    /// one was already shown today, and between two languages of which
    /// neither, or both, are mine.
    public static func hint(
        for direction: Direction, myLanguage: LanguageCode, words: Int,
        lastHintDay: LearningDay?, today: LearningDay
    ) -> TranslateHint? {
        if words < minimumWords { return nil }
        if lastHintDay == today { return nil }
        let mine = myLanguage.baseSubtag
        let fromMine = direction.source.baseSubtag == mine
        let intoMine = direction.target.baseSubtag == mine
        if fromMine == intoMine { return nil }
        if fromMine { return .write(direction.target) }
        return .explain
    }

    /// The action the hint points to.
    public var action: Action {
        switch self {
        case .write: return .correct
        case .explain: return .explain
        }
    }

    /// `hotKey` is that action's, as written in config.json; nil when it
    /// has none.
    public func text(languages: [LanguageConfig], hotKey: String?) -> String {
        var keys = ""
        if let hotKey { keys = " (\(hotKey))" }
        switch self {
        case .write(let target):
            let name = Milestone.name(of: target, in: languages)
            return "Next time, try writing it in \(name) yourself, then press Correct\(keys)."
        case .explain:
            return "Want to see how this text works? Try Explain\(keys)."
        }
    }

    /// The action's hotkey as the file writes it: its own text, the
    /// default when the file does not name it, nil when it is off.
    public static func hotKey(for action: Action, in bindings: HotKeyBindings?) -> String? {
        guard let bindings else { return HotKeyBindings.defaultText(for: action) }
        switch bindings.binding(for: action) {
        case .off:
            return nil
        case .useDefault:
            return HotKeyBindings.defaultText(for: action)
        case .text(let written):
            return written
        }
    }
}
