import Foundation

/// A pressed shortcut as config.json writes it, and a refused one as the
/// settings window says it (#61).
public enum HotKeyText {

    /// "control+option+T" -- macOS's modifier order, then the key: a named
    /// key by its name, else what the layout types, a letter in capitals.
    /// Nil when the key has neither, types something the file's syntax
    /// cannot hold (a space, "+"), or would read back as another key: a
    /// keypad digit, or the second of two keys typing the same character.
    public static func text(keyCode: UInt32, modifiers: UInt32, layout: KeyLayout) -> String? {
        guard let key = keyName(keyCode, layout) else { return nil }
        var parts: [String] = []
        if modifiers & HotKeySpec.control != 0 { parts.append("control") }
        if modifiers & HotKeySpec.option != 0 { parts.append("option") }
        if modifiers & HotKeySpec.shift != 0 { parts.append("shift") }
        if modifiers & HotKeySpec.command != 0 { parts.append("command") }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    /// A whole sentence for under the recorder.
    public static func sentence(_ problem: HotKeyProblem) -> String {
        switch problem {
        case .needsModifier:
            return "Use Command, Control or Option with the key."
        case .sharedWith(let action), .previousTakenBy(let action):
            return "Already the \(action.displayName) hotkey."
        case .notOnLayout(let character):
            return "\"\(character)\" can't be typed on this keyboard layout."
        case .empty, .emptyPart, .unknownPart, .noKey, .severalKeys:
            return "lingoSwen can't use this key as a hotkey."
        }
    }

    private static func keyName(_ keyCode: UInt32, _ layout: KeyLayout) -> String? {
        for named in NamedKey.allCases {
            if named.keyCode == keyCode { return named.rawValue }
        }
        guard let typed = layout.characters[keyCode] else { return nil }
        if typed.count != 1 { return nil }
        if typed == "+" { return nil }
        if typed.allSatisfy(\.isWhitespace) { return nil }
        let back = layout.resolve(HotKeySpec(modifiers: 0, key: .character(typed.lowercased())))
        guard case .success(let combination) = back else { return nil }
        if combination.keyCode != keyCode { return nil }
        return capital(typed)
    }

    /// A letter in capitals, as people write shortcuts -- unless its capital
    /// is more than one character ("SS" for an eszett), which the file's
    /// syntax would read as two keys.
    private static func capital(_ typed: String) -> String {
        let upper = typed.uppercased()
        if upper.count != 1 { return typed }
        return upper
    }
}
