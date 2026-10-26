import Foundation

/// Why the settings window did not write a value (#61). The file keeps its
/// last good value; `message` is shown under the control.
public enum SettingsRefusal: Error, Sendable, Equatable {
    /// Translate needs a pair.
    case tooFewLanguages
    case unknownLanguage(LanguageCode)
    /// My language (#81) must stay on; carries its display name.
    case isMyLanguage(String)
    /// Only an enabled language can be my language; carries its name.
    case languageOff(String)
    /// The value is outside the range `message` names.
    case outOfRange(String)
    case emptyModel
    case hotKey(HotKeyProblem)
    case noSuchAudience(String)
    case emptyName
    case nameTooLong
    case nameInUse(String)
    case lastAudience
    case noSuchRow
    case emptyTerm
    case termTooLong
    /// The term, and the language whose column already has it.
    case termInUse(String, String)
    case tooManyRows
    case dntInUse(String)
    case tooManyTerms
    /// A do-not-translate term of one character, or one holding the
    /// masking brackets.
    case unusableTerm

    public var message: String {
        switch self {
        case .tooFewLanguages:
            return "At least two languages stay on."
        case .unknownLanguage(let code):
            return "\(code.rawValue) is not a configured language."
        case .isMyLanguage(let name):
            return "\(name) is your language; choose another first."
        case .languageOff(let name):
            return "Switch \(name) on first."
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
        case .noSuchRow:
            return "That row is no longer there."
        case .emptyTerm:
            return "Enter a term."
        case .termTooLong:
            return "At most \(SettingsEditor.maximumTermLength) characters."
        case .termInUse(let term, let language):
            return "\(term) is already in another row for \(language)."
        case .tooManyRows:
            return "At most \(SettingsEditor.maximumConcepts) rows."
        case .dntInUse(let term):
            return "\(term) is already in the list."
        case .tooManyTerms:
            return "At most \(SettingsEditor.maximumDoNotTranslate) terms."
        case .unusableTerm:
            return "Use at least two characters, and not \u{27E6} or \u{27E7}."
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
    public static let maximumConcepts = 200
    public static let maximumDoNotTranslate = 100

    public private(set) var configuration: Configuration

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    public mutating func setLanguage(_ code: LanguageCode, enabled: Bool) throws {
        var languages = configuration.languages
        guard let index = languages.firstIndex(where: { $0.code == code }) else {
            throw SettingsRefusal.unknownLanguage(code)
        }
        if !enabled {
            if code == configuration.myLanguageCode {
                throw SettingsRefusal.isMyLanguage(languages[index].displayName)
            }
        }
        languages[index].enabled = enabled
        if languages.filter(\.enabled).count < Self.minimumLanguages {
            throw SettingsRefusal.tooFewLanguages
        }
        configuration.languages = languages
    }

    /// The language explanations are written in (#81): an enabled one.
    public mutating func setMyLanguage(_ code: LanguageCode) throws {
        guard let language = configuration.language(for: code) else {
            throw SettingsRefusal.unknownLanguage(code)
        }
        guard language.enabled else {
            throw SettingsRefusal.languageOff(language.displayName)
        }
        configuration.myLanguage = code
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

    /// Which Ollama to talk to (#126). The models stay as they are: the
    /// other server is asked for the same names.
    public mutating func setModelServer(_ server: ModelServer) {
        configuration.modelServer = server
    }

    // MARK: - Audiences

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
            if nameInUse(shipped.name, except: nil) || nameInUse(shipped.id, except: nil) {
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

    /// Another audience's name or id, ignoring case; `except` is the
    /// audience being renamed. An id counts because inference matches a
    /// model's answer by id before name, and the prompt lists both.
    private func nameInUse(_ name: String, except id: String?) -> Bool {
        let wanted = name.lowercased()
        for profile in configuration.profiles {
            if profile.id == id { continue }
            if profile.name.lowercased() == wanted { return true }
            if profile.id.lowercased() == wanted { return true }
        }
        return false
    }

    // MARK: - Glossary (#59)

    /// Trimmed; empty removes the language from the row, and a row left
    /// with no terms is removed. `index == concepts.count` appends a row,
    /// so an empty row is never stored.
    public mutating func setTerm(_ term: String, for language: LanguageCode, inConcept index: Int) throws {
        var concepts = configuration.glossary.concepts
        if index < 0 { throw SettingsRefusal.noSuchRow }
        if index > concepts.count { throw SettingsRefusal.noSuchRow }
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > Self.maximumTermLength { throw SettingsRefusal.termTooLong }
        if !trimmed.isEmpty {
            try checkTermFree(trimmed, language, except: index)
        }
        if index == concepts.count {
            if trimmed.isEmpty { return }
            if concepts.count >= Self.maximumConcepts { throw SettingsRefusal.tooManyRows }
            concepts.append(GlossaryConcept())
        }
        concepts[index].set(trimmed, for: language)
        if concepts[index].isEmpty { concepts.remove(at: index) }
        configuration.glossary.concepts = concepts
    }

    public mutating func deleteConcepts(at indexes: IndexSet) throws {
        for index in indexes {
            if index >= configuration.glossary.concepts.count { throw SettingsRefusal.noSuchRow }
        }
        // Highest first, so each index still means the row it named.
        for index in indexes.reversed() { configuration.glossary.concepts.remove(at: index) }
    }

    /// Ignoring case, per language: two rows giving "Modul" for German would
    /// make German to English ambiguous. Another language may share it.
    private func checkTermFree(_ term: String, _ language: LanguageCode, except index: Int) throws {
        let wanted = term.lowercased()
        for (other, concept) in configuration.glossary.concepts.enumerated() {
            if other == index { continue }
            guard let existing = concept.terms[language] else { continue }
            if existing.lowercased() == wanted {
                let name = configuration.language(for: language)?.displayName ?? language.rawValue
                throw SettingsRefusal.termInUse(term, name)
            }
        }
    }

    // MARK: - Do not translate (#59)

    /// Matched exactly when masking, so only an exact duplicate is refused.
    public mutating func addDoNotTranslate(_ term: String) throws {
        let checked = try checkedDoNotTranslate(term, except: nil)
        if configuration.doNotTranslate.count >= Self.maximumDoNotTranslate {
            throw SettingsRefusal.tooManyTerms
        }
        configuration.doNotTranslate.append(checked)
    }

    /// Empty deletes it.
    public mutating func setDoNotTranslate(_ term: String, at index: Int) throws {
        if index < 0 { throw SettingsRefusal.noSuchRow }
        if index >= configuration.doNotTranslate.count { throw SettingsRefusal.noSuchRow }
        if term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            configuration.doNotTranslate.remove(at: index)
            return
        }
        configuration.doNotTranslate[index] = try checkedDoNotTranslate(term, except: index)
    }

    public mutating func deleteDoNotTranslate(at indexes: IndexSet) throws {
        for index in indexes {
            if index >= configuration.doNotTranslate.count { throw SettingsRefusal.noSuchRow }
        }
        for index in indexes.reversed() { configuration.doNotTranslate.remove(at: index) }
    }

    private func checkedDoNotTranslate(_ term: String, except index: Int?) throws -> String {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw SettingsRefusal.emptyTerm }
        if trimmed.count > Self.maximumTermLength { throw SettingsRefusal.termTooLong }
        // One character masks every occurrence of it ("a"); the brackets
        // are the sentinels' own (`TokenProtector`).
        if trimmed.count < 2 { throw SettingsRefusal.unusableTerm }
        if trimmed.contains("\u{27E6}") { throw SettingsRefusal.unusableTerm }
        if trimmed.contains("\u{27E7}") { throw SettingsRefusal.unusableTerm }
        for (other, existing) in configuration.doNotTranslate.enumerated() {
            if other == index { continue }
            if existing == trimmed { throw SettingsRefusal.dntInUse(trimmed) }
        }
        return trimmed
    }
}
