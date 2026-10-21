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
    case noSuchAudience(String)
    case emptyName
    case nameTooLong
    case nameInUse(String)
    case lastAudience

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
        case .noSuchAudience(let id):
            return "There is no audience \(id)."
        case .emptyName:
            return "Enter a name."
        case .nameTooLong:
            return "At most \(SettingsEditor.maximumNameLength) characters."
        case .nameInUse(let name):
            return "Another audience is called \(name)."
        case .lastAudience:
            return "At least one audience stays."
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
    public static let maximumNameLength = 40
    public static let maximumGuidanceLength = 2_000
    public static let maximumTerms = 50
    public static let maximumTermLength = 80
    public static let newAudienceName = "New audience"

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

    // MARK: - Audiences

    /// "New audience", or "New audience 2", ... when that is taken.
    public func newAudienceName() -> String {
        let base = Self.newAudienceName
        if !nameInUse(base, except: nil) { return base }
        for number in 2...(configuration.profiles.count + 2) {
            let candidate = base + " " + String(number)
            if !nameInUse(candidate, except: nil) { return candidate }
        }
        return base + " " + String(configuration.profiles.count + 3)
    }

    /// Sie, no guidance, no terms; returns the new id.
    public mutating func addAudience(named name: String) throws -> String {
        let checked = try checkedName(name, except: nil)
        let id = AudienceID.make(from: checked, taken: Set(configuration.profiles.map(\.id)))
        configuration.profiles.append(
            AudienceProfile(id: id, name: checked, register: .formal, toneGuidance: ""))
        return id
    }

    /// The id stays as it is.
    public mutating func renameAudience(_ id: String, to name: String) throws {
        let index = try audienceIndex(id)
        configuration.profiles[index].name = try checkedName(name, except: id)
    }

    public mutating func setRegister(_ register: Register, forAudience id: String) throws {
        let index = try audienceIndex(id)
        configuration.profiles[index].register = register
    }

    /// Trimmed; at most `maximumGuidanceLength` characters.
    public mutating func setToneGuidance(_ text: String, forAudience id: String) throws {
        let index = try audienceIndex(id)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > Self.maximumGuidanceLength {
            throw SettingsRefusal.outOfRange("At most 2,000 characters")
        }
        configuration.profiles[index].toneGuidance = trimmed
    }

    /// One term per line, each trimmed; blank lines dropped.
    public mutating func setPreferredTerms(_ lines: String, forAudience id: String) throws {
        let index = try audienceIndex(id)
        var terms: [String] = []
        for line in lines.split(whereSeparator: \.isNewline) {
            let term = line.trimmingCharacters(in: .whitespaces)
            if term.isEmpty { continue }
            if term.count > Self.maximumTermLength {
                throw SettingsRefusal.outOfRange("A term has at most 80 characters")
            }
            terms.append(term)
        }
        if terms.count > Self.maximumTerms {
            throw SettingsRefusal.outOfRange("At most 50 terms")
        }
        configuration.profiles[index].glossaryBias = terms
    }

    /// Never the last one.
    public mutating func deleteAudience(_ id: String) throws {
        let index = try audienceIndex(id)
        if configuration.profiles.count <= 1 { throw SettingsRefusal.lastAudience }
        configuration.profiles.remove(at: index)
    }

    /// Adds back, at the end, each shipped audience whose id is missing --
    /// unless its name is now another audience's.
    public mutating func restoreShippedAudiences() -> (restored: [String], skipped: [String]) {
        var restored: [String] = []
        var skipped: [String] = []
        for shipped in AudienceProfile.shippedDefaults {
            if configuration.profile(id: shipped.id) != nil { continue }
            if nameInUse(shipped.name, except: nil) {
                skipped.append(shipped.name)
                continue
            }
            configuration.profiles.append(shipped)
            restored.append(shipped.name)
        }
        return (restored, skipped)
    }

    private func audienceIndex(_ id: String) throws -> Int {
        for (index, profile) in configuration.profiles.enumerated() {
            if profile.id == id { return index }
        }
        throw SettingsRefusal.noSuchAudience(id)
    }

    private func checkedName(_ name: String, except id: String?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw SettingsRefusal.emptyName }
        if trimmed.count > Self.maximumNameLength { throw SettingsRefusal.nameTooLong }
        if nameInUse(trimmed, except: id) { throw SettingsRefusal.nameInUse(trimmed) }
        return trimmed
    }

    /// Ignoring case; `except` is the audience being renamed.
    private func nameInUse(_ name: String, except id: String?) -> Bool {
        let wanted = name.lowercased()
        for profile in configuration.profiles {
            if profile.id == id { continue }
            if profile.name.lowercased() == wanted { return true }
        }
        return false
    }
}
