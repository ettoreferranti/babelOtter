import Foundation

/// One action's hotkey as written in config.json (#26).
public enum HotKeyBinding: Sendable, Equatable {
    /// The action is not in the file: its default applies.
    case useDefault
    /// JSON null: no hotkey, the menu only.
    case off
    /// As written, parsed later by `HotKeySpec`.
    case text(String)
}

/// The `hotkeys` object in config.json.
///
/// Text rather than key codes, parsed by `HotKeySpec` and resolved against
/// the keyboard layout by `KeyLayout`, so a typo in a hotkey is reported on
/// its own and never costs the rest of the file.
public struct HotKeyBindings: Sendable, Equatable, Codable {
    public var translate: HotKeyBinding
    public var correct: HotKeyBinding
    public var explain: HotKeyBinding
    public var repitch: HotKeyBinding

    public init(
        translate: HotKeyBinding = .useDefault, correct: HotKeyBinding = .useDefault,
        explain: HotKeyBinding = .useDefault, repitch: HotKeyBinding = .useDefault
    ) {
        self.translate = translate
        self.correct = correct
        self.explain = explain
        self.repitch = repitch
    }

    public static let defaults = HotKeyBindings(
        translate: .text("control+option+T"), correct: .text("control+option+C"),
        explain: .text("control+option+E"), repitch: .text("control+option+R"))

    /// Every action has a default.
    public static func defaultText(for action: Action) -> String? {
        switch action {
        case .translate:
            return "control+option+T"
        case .correct:
            return "control+option+C"
        case .explain:
            return "control+option+E"
        case .repitch:
            return "control+option+R"
        }
    }

    public func binding(for action: Action) -> HotKeyBinding {
        switch action {
        case .translate:
            return translate
        case .correct:
            return correct
        case .explain:
            return explain
        case .repitch:
            return repitch
        }
    }

    public mutating func set(_ binding: HotKeyBinding, for action: Action) {
        switch action {
        case .translate:
            translate = binding
        case .correct:
            correct = binding
        case .explain:
            explain = binding
        case .repitch:
            repitch = binding
        }
    }

    private enum CodingKeys: String, CodingKey {
        case translate
        case correct
        case explain
        case repitch
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        translate = try Self.decode(.translate, in: container)
        correct = try Self.decode(.correct, in: container)
        explain = try Self.decode(.explain, in: container)
        repitch = try Self.decode(.repitch, in: container)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try Self.encode(translate, as: .translate, in: &container)
        try Self.encode(correct, as: .correct, in: &container)
        try Self.encode(explain, as: .explain, in: &container)
        try Self.encode(repitch, as: .repitch, in: &container)
    }

    /// Absent and null are different answers: absent is the default, null
    /// is "no hotkey".
    private static func decode(
        _ key: CodingKeys, in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> HotKeyBinding {
        if !container.contains(key) {
            return .useDefault
        }
        if try container.decodeNil(forKey: key) {
            return .off
        }
        return .text(try container.decode(String.self, forKey: key))
    }

    private static func encode(
        _ binding: HotKeyBinding, as key: CodingKeys,
        in container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch binding {
        case .useDefault:
            return
        case .off:
            try container.encodeNil(forKey: key)
        case .text(let text):
            try container.encode(text, forKey: key)
        }
    }
}
