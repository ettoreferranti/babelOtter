import Foundation

/// A BCP-47-ish language tag, normalised so that two spellings of the same
/// language are the same value.
///
/// Normalisation is not cosmetic. `FR-CFG-03` invites the user to hand-edit the
/// configuration file, so `de-CH`, `de-ch` and a stray `" de-CH\n"` all reach us
/// as the same intent and must compare equal -- otherwise a capital letter in a
/// text editor silently disables a language.
public struct LanguageCode: Sendable, Hashable, Codable, CustomStringConvertible {

    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The part before the first `-`: `de-ch` becomes `de`.
    ///
    /// Detection and configuration disagree about regions on purpose.
    /// `NLLanguageRecognizer` reports `de`, while the language the user enabled
    /// is `de-CH` -- Swiss orthography being a locale rule, not a separate
    /// language. Comparing full tags would report German as "not enabled" for
    /// every German selection, so ``TargetLanguageResolver`` matches on this.
    public var baseSubtag: LanguageCode {
        guard let separator = rawValue.firstIndex(of: "-") else { return self }
        return LanguageCode(String(rawValue[rawValue.startIndex..<separator]))
    }

    public var description: String { rawValue }

    /// Encodes as a bare string so the configuration file reads as
    /// `"code": "de-ch"` rather than as a nested object.
    public init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One literal substitution applied to model output for a given language.
///
/// Deliberately not a regular expression. `FR-LNG-02` wants rules attachable by
/// configuration, and a regex in a hand-edited file is both a foot-gun and a way
/// to make post-processing backtrack catastrophically over the user's own text.
/// A literal pair covers the case the spec actually names -- `eszett` -> `ss` -- and can
/// be read by someone who has never written a regex.
public struct LocaleRule: Sendable, Equatable, Codable {

    public let replace: String
    public let with: String

    public init(replace: String, with: String) {
        self.replace = replace
        self.with = with
    }
}

/// How a language addresses a reader formally and informally (#110):
/// Sie/du, Lei/tu, vous/tu. A language without the distinction (English)
/// has none.
public struct AddressForms: Sendable, Equatable, Codable {
    public let formal: String
    public let informal: String

    public init(formal: String, informal: String) {
        self.formal = formal
        self.informal = informal
    }

    public func form(for register: Register) -> String {
        switch register {
        case .formal: return formal
        case .informal: return informal
        }
    }

    static let expected = "expected a formal and an informal form"

    /// Both forms must be there and not blank.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let formal = try container.decode(String.self, forKey: .formal)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let informal = try container.decode(String.self, forKey: .informal)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if formal.isEmpty || informal.isEmpty {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: Self.expected))
        }
        self.init(formal: formal, informal: informal)
    }
}

/// A language babelOtter can translate to or from, defined entirely as data.
///
/// `FR-LNG-01` says no language is hardcoded in logic, and `FR-LNG-03` says
/// adding one must require no code change. Both are only true if everything that
/// distinguishes a language -- including its orthographic quirks -- lives in a
/// value like this one.
public struct LanguageConfig: Sendable, Equatable, Codable {

    public let code: LanguageCode
    public let displayName: String
    public let localeRules: [LocaleRule]
    public var enabled: Bool
    /// Nil for a language without a formal/informal distinction (#110).
    public let addressForms: AddressForms?

    public init(
        code: LanguageCode, displayName: String, localeRules: [LocaleRule], enabled: Bool,
        addressForms: AddressForms? = nil
    ) {
        self.code = code
        self.displayName = displayName
        self.localeRules = localeRules
        self.enabled = enabled
        self.addressForms = addressForms
    }

    private enum CodingKeys: String, CodingKey {
        case code, displayName, localeRules, enabled, addressForms
    }

    /// `addressForms` absent -- a file from before #110 -- takes the shipped
    /// language's forms for the same code, so de-ch keeps Sie/du with no
    /// edit and no language is named in logic; `null` means none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let code = try container.decode(LanguageCode.self, forKey: .code)
        var forms: AddressForms?
        if container.contains(.addressForms) {
            forms = try container.decodeIfPresent(AddressForms.self, forKey: .addressForms)
        } else {
            forms = Self.shippedDefaults.first { $0.code == code }?.addressForms
        }
        self.init(
            code: code,
            displayName: try container.decode(String.self, forKey: .displayName),
            localeRules: try container.decode([LocaleRule].self, forKey: .localeRules),
            enabled: try container.decode(Bool.self, forKey: .enabled),
            addressForms: forms)
    }

    /// Always writes `addressForms`, `null` for none, so the file shows it.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(localeRules, forKey: .localeRules)
        try container.encode(enabled, forKey: .enabled)
        if let addressForms {
            try container.encode(addressForms, forKey: .addressForms)
        } else {
            try container.encodeNil(forKey: .addressForms)
        }
    }
}

extension LanguageConfig {

    public static let english = LanguageConfig(
        code: LanguageCode("en"),
        displayName: "English",
        localeRules: [],
        enabled: true
    )

    /// Swiss Standard German. The single rule here is the whole of `FR-TRN-05`:
    /// the eszett never appears in Swiss orthography, always `ss`.
    public static let swissGerman = LanguageConfig(
        code: LanguageCode("de-CH"),
        displayName: "Swiss Standard German",
        // "\u{00DF}" is the eszett. Written as an escape for the ASCII-only
        // source rule -- see AsciiSourceTests.
        localeRules: [LocaleRule(replace: "\u{00DF}", with: "ss")],
        enabled: true,
        addressForms: AddressForms(formal: "Sie", informal: "du")
    )

    /// What a fresh install gets: English and de-CH, both enabled (`FR-LNG-03`).
    public static let shippedDefaults: [LanguageConfig] = [.english, .swissGerman]
}
