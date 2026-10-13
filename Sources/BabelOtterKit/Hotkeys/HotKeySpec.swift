import Foundation

/// A key whose position is the same on every layout, with its virtual key
/// code (`kVK_*` from Carbon's Events.h, written as literals because the kit
/// cannot import Carbon).
public enum NamedKey: String, Sendable, Equatable, CaseIterable {
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10
    case f11, f12, f13, f14, f15, f16, f17, f18, f19, f20
    case space
    case returnKey = "return"
    case tab, escape, delete, left, right, up, down

    public var keyCode: UInt32 {
        switch self {
        case .f1: return 0x7A
        case .f2: return 0x78
        case .f3: return 0x63
        case .f4: return 0x76
        case .f5: return 0x60
        case .f6: return 0x61
        case .f7: return 0x62
        case .f8: return 0x64
        case .f9: return 0x65
        case .f10: return 0x6D
        case .f11: return 0x67
        case .f12: return 0x6F
        case .f13: return 0x69
        case .f14: return 0x6B
        case .f15: return 0x71
        case .f16: return 0x6A
        case .f17: return 0x40
        case .f18: return 0x4F
        case .f19: return 0x50
        case .f20: return 0x5A
        case .space: return 0x31
        case .returnKey: return 0x24
        case .tab: return 0x30
        case .escape: return 0x35
        case .delete: return 0x33
        case .left: return 0x7B
        case .right: return 0x7C
        case .down: return 0x7D
        case .up: return 0x7E
        }
    }

    /// "F5", "Space", "Return".
    public var label: String {
        rawValue.capitalized
    }
}

public enum HotKeyKey: Sendable, Equatable {
    /// One character, lowercased; resolved through the keyboard layout.
    case character(String)
    case named(NamedKey)
}

/// Why a hotkey from config.json is not used. `detail` follows the hotkey's
/// text in the menu: `translate hotkey "contrl+option+T": <detail>`.
public enum HotKeyProblem: Error, Sendable, Equatable {
    case empty
    case emptyPart
    case unknownPart(String)
    case noKey
    case severalKeys
    case needsModifier
    case notOnLayout(String)
    case sharedWith(Action)
    /// The previous combination could not be kept: another action now has it.
    case previousTakenBy(Action)

    public var detail: String {
        switch self {
        case .empty:
            return "is empty"
        case .emptyPart:
            return "has an empty part (\"+\" cannot be the key)"
        case .unknownPart(let part):
            return "unknown key or modifier \"\(part)\""
        case .noKey:
            return "names no key"
        case .severalKeys:
            return "names more than one key"
        case .needsModifier:
            return "needs control, option or command"
        case .notOnLayout(let character):
            return "\"\(character)\" can't be typed on the current keyboard layout"
        case .sharedWith(let action):
            return "is also the \(action.displayName) hotkey"
        case .previousTakenBy(let action):
            return "so this action has no hotkey: its previous one is now the \(action.displayName) hotkey"
        }
    }
}

/// A hotkey as written, parsed but not yet tied to a key position.
public struct HotKeySpec: Sendable, Equatable {
    /// Carbon modifier bits.
    public let modifiers: UInt32
    public let key: HotKeyKey

    public init(modifiers: UInt32, key: HotKeyKey) {
        self.modifiers = modifiers
        self.key = key
    }

    /// Carbon's `cmdKey`, `shiftKey`, `optionKey`, `controlKey`.
    public static let command: UInt32 = 0x100
    public static let shift: UInt32 = 0x200
    public static let option: UInt32 = 0x800
    public static let control: UInt32 = 0x1000

    /// "control+option+T": modifiers and one key joined by "+", in any order
    /// and case. Shift alone is refused: it would fire on every capital.
    public static func parse(_ text: String) -> Result<HotKeySpec, HotKeyProblem> {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return .failure(.empty)
        }
        var modifiers: UInt32 = 0
        var key: HotKeyKey?
        for rawPart in trimmed.split(separator: "+", omittingEmptySubsequences: false) {
            let part = rawPart.trimmingCharacters(in: .whitespaces).lowercased()
            if part.isEmpty {
                return .failure(.emptyPart)
            }
            if let bit = modifierBit(part) {
                modifiers |= bit
                continue
            }
            guard let parsed = keyFor(part) else {
                return .failure(.unknownPart(part))
            }
            if key != nil {
                return .failure(.severalKeys)
            }
            key = parsed
        }
        guard let key else {
            return .failure(.noKey)
        }
        if modifiers & (command | option | control) == 0 {
            return .failure(.needsModifier)
        }
        return .success(HotKeySpec(modifiers: modifiers, key: key))
    }

    /// "Control-Option-Shift-Command-Z": macOS's modifier order.
    public static func displayName(modifiers: UInt32, keyLabel: String) -> String {
        var name = ""
        if modifiers & control != 0 {
            name += "Control-"
        }
        if modifiers & option != 0 {
            name += "Option-"
        }
        if modifiers & shift != 0 {
            name += "Shift-"
        }
        if modifiers & command != 0 {
            name += "Command-"
        }
        return name + keyLabel
    }

    private static func modifierBit(_ part: String) -> UInt32? {
        switch part {
        case "control", "ctrl":
            return control
        case "option", "alt":
            return option
        case "command", "cmd":
            return command
        case "shift":
            return shift
        default:
            return nil
        }
    }

    private static func keyFor(_ part: String) -> HotKeyKey? {
        if let named = NamedKey(rawValue: part) {
            return .named(named)
        }
        if part.count == 1 {
            return .character(part)
        }
        return nil
    }
}
