import Foundation

/// A BCP-47-ish language tag, normalised so that two spellings of the same
/// language are the same value.
///
/// Normalisation is not cosmetic. `FR-CFG-03` invites the user to hand-edit the
/// configuration file, so `de-CH`, `de-ch` and a stray `" de-CH\n"` all reach us
/// as the same intent and must compare equal — otherwise a capital letter in a
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
    /// is `de-CH` — Swiss orthography being a locale rule, not a separate
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
/// A literal pair covers the case the spec actually names — `ß` → `ss` — and can
/// be read by someone who has never written a regex.
public struct LocaleRule: Sendable, Equatable, Codable {

    public let replace: String
    public let with: String

    public init(replace: String, with: String) {
        self.replace = replace
        self.with = with
    }
}

/// A language babelOtter can translate to or from, defined entirely as data.
///
/// `FR-LNG-01` says no language is hardcoded in logic, and `FR-LNG-03` says
/// adding one must require no code change. Both are only true if everything that
/// distinguishes a language — including its orthographic quirks — lives in a
/// value like this one.
public struct LanguageConfig: Sendable, Equatable, Codable {

    public let code: LanguageCode
    public let displayName: String
    public let localeRules: [LocaleRule]
    public var enabled: Bool

    public init(code: LanguageCode, displayName: String, localeRules: [LocaleRule], enabled: Bool) {
        self.code = code
        self.displayName = displayName
        self.localeRules = localeRules
        self.enabled = enabled
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
    /// `ß` never appears in Swiss orthography, always `ss`.
    public static let swissGerman = LanguageConfig(
        code: LanguageCode("de-CH"),
        displayName: "Swiss Standard German",
        localeRules: [LocaleRule(replace: "ß", with: "ss")],
        enabled: true
    )

    /// What a fresh install gets: English and de-CH, both enabled (`FR-LNG-03`).
    public static let shippedDefaults: [LanguageConfig] = [.english, .swissGerman]
}
