import Foundation

/// What each key types on the current keyboard layout, with no modifiers.
///
/// Carbon registers key positions, not characters. The app reads this table
/// from macOS (`UCKeyTranslate`) so that "control+option+Z" is the key
/// labelled Z on the layout in use, which on Swiss German is not the US Z.
public struct KeyLayout: Sendable, Equatable {
    public let characters: [UInt32: String]

    public init(characters: [UInt32: String]) {
        self.characters = characters
    }

    /// The letters A to Z on a US keyboard, by `kVK_ANSI_*` code. Used when
    /// macOS reports no layout at all.
    public static let usANSI = KeyLayout(characters: [
        0x00: "a", 0x0B: "b", 0x08: "c", 0x02: "d", 0x0E: "e", 0x03: "f", 0x05: "g",
        0x04: "h", 0x22: "i", 0x26: "j", 0x28: "k", 0x25: "l", 0x2E: "m", 0x2D: "n",
        0x1F: "o", 0x23: "p", 0x0C: "q", 0x0F: "r", 0x01: "s", 0x11: "t", 0x20: "u",
        0x09: "v", 0x0D: "w", 0x07: "x", 0x10: "y", 0x06: "z",
    ])

    public func resolve(_ spec: HotKeySpec) -> Result<HotKeyCombination, HotKeyProblem> {
        switch spec.key {
        case .named(let named):
            return .success(HotKeyCombination(
                keyCode: named.keyCode, modifiers: spec.modifiers,
                displayName: HotKeySpec.displayName(modifiers: spec.modifiers, keyLabel: named.label)))
        case .character(let character):
            guard let code = keyCode(typing: character) else {
                return .failure(.notOnLayout(character))
            }
            return .success(HotKeyCombination(
                keyCode: code, modifiers: spec.modifiers,
                displayName: HotKeySpec.displayName(
                    modifiers: spec.modifiers, keyLabel: character.uppercased())))
        }
    }

    /// The lowest code that types it, so the answer never depends on
    /// dictionary order (an ISO keyboard has two keys typing "<").
    private func keyCode(typing character: String) -> UInt32? {
        var best: UInt32?
        for (code, typed) in characters where typed.lowercased() == character {
            if let current = best {
                if code < current {
                    best = code
                }
            } else {
                best = code
            }
        }
        return best
    }
}

extension HotKeyCombination {
    /// The same key and modifiers, whatever each is called.
    public func sameKeys(as other: HotKeyCombination) -> Bool {
        if keyCode != other.keyCode {
            return false
        }
        return modifiers == other.modifiers
    }
}
