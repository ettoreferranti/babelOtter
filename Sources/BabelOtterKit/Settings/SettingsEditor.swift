import Foundation

/// Why the settings window did not write a value (#61). The file keeps its
/// last good value; `message` is shown under the control.
public enum SettingsRefusal: Error, Sendable, Equatable {
    /// Translate needs a pair.
    case tooFewLanguages
    case unknownLanguage(LanguageCode)
    /// The value is outside the range `message` names.
    case outOfRange(String)
    case emptyModel
    case hotKey(HotKeyProblem)

    public var message: String {
        switch self {
        case .tooFewLanguages:
            return "At least two languages stay on."
        case .unknownLanguage(let code):
            return "\(code.rawValue) is not a configured language."
        case .outOfRange(let range):
            return range
        case .emptyModel:
            return "Choose a model."
        case .hotKey(let problem):
            return HotKeyText.sentence(problem)
        }
    }
}

/// The settings window's edits, checked before they change anything (#61).
///
/// Each method either changes `configuration` or throws a `SettingsRefusal`
/// and leaves it as it was, so nothing the window writes can fail to load.
public struct SettingsEditor: Sendable, Equatable {

    public static let minimumLanguages = 2
    public static let timeoutRange: ClosedRange<Double> = 5...600
    public static let retentionDaysRange: ClosedRange<Int> = 1...36_500

    public private(set) var configuration: Configuration

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    public mutating func setLanguage(_ code: LanguageCode, enabled: Bool) throws {
        var languages = configuration.languages
        guard let index = languages.firstIndex(where: { $0.code == code }) else {
            throw SettingsRefusal.unknownLanguage(code)
        }
        languages[index].enabled = enabled
        if languages.filter(\.enabled).count < Self.minimumLanguages {
            throw SettingsRefusal.tooFewLanguages
        }
        configuration.languages = languages
    }

    public mutating func setRetention(_ retention: HistoryRetention) throws {
        if case .days(let days) = retention {
            if !Self.retentionDaysRange.contains(days) {
                throw SettingsRefusal.outOfRange("Between 1 and 36,500 days")
            }
        }
        configuration.retentionDays = retention
    }

    public mutating func setTimeout(seconds: Double) throws {
        if !Self.timeoutRange.contains(seconds) {
            throw SettingsRefusal.outOfRange("Between 5 and 600 seconds")
        }
        configuration.timeoutSeconds = seconds
    }

    public mutating func setStrictCaptureOnly(_ on: Bool) {
        configuration.strictCaptureOnly = on
    }

    /// `.text` is parsed and resolved as the file's would be, and refused
    /// when another action has the same keys -- checked against each other
    /// action directly, so the refusal is about the row being edited.
    public mutating func setHotKey(_ binding: HotKeyBinding, for action: Action, layout: KeyLayout) throws {
        var bindings = configuration.hotkeys ?? HotKeyBindings()
        if let wanted = try Self.combination(binding, for: action, layout: layout) {
            for other in HotKeyPlan.actions where other != action {
                let theirs = try? Self.combination(bindings.binding(for: other), for: other, layout: layout)
                // Another action's hotkey that does not resolve takes no keys.
                if let theirs {
                    if theirs.sameKeys(as: wanted) {
                        throw SettingsRefusal.hotKey(.sharedWith(other))
                    }
                }
            }
        }
        bindings.set(binding, for: action)
        configuration.hotkeys = bindings
    }

    /// Nil when the action has no hotkey.
    private static func combination(
        _ binding: HotKeyBinding, for action: Action, layout: KeyLayout
    ) throws -> HotKeyCombination? {
        let text: String
        switch binding {
        case .off:
            return nil
        case .useDefault:
            guard let fallback = HotKeyBindings.defaultText(for: action) else { return nil }
            text = fallback
        case .text(let written):
            text = written
        }
        switch HotKeySpec.parse(text) {
        case .failure(let problem):
            throw SettingsRefusal.hotKey(problem)
        case .success(let spec):
            switch layout.resolve(spec) {
            case .failure(let problem):
                throw SettingsRefusal.hotKey(problem)
            case .success(let combination):
                return combination
            }
        }
    }

    /// Trimmed; an empty name is refused.
    public mutating func setModel(_ model: String, for action: Action) throws {
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw SettingsRefusal.emptyModel }
        configuration.models[action] = name
    }
}
