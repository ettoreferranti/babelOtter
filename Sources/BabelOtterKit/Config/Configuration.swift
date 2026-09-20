import Foundation

/// The four things babelOtter can do to a selection.
///
/// Lives in the configuration layer rather than the LLM layer because
/// configuration is what enumerates it: `FR-CFG-02` keys a model per action, and
/// `FR-UI-01` keys a hotkey per action.
public enum Action: String, Sendable, Codable, CaseIterable {
    case translate
    case correct
    case explain
    case repitch
}

/// Everything the user can configure, as one value (spec section 6).
///
/// `FR-CFG-03` stores this as a human-readable file, which shapes the type: no
/// UUIDs, no opaque blobs, and every field a person could reasonably want to
/// change by hand is a named scalar rather than something derived.
public struct Configuration: Sendable, Equatable, Codable {

    public var languages: [LanguageConfig]
    public var profiles: [AudienceProfile]
    public var glossary: Glossary
    /// Terms masked to sentinels before generation and restored verbatim after
    /// (`FR-GLO-02`). See ``TokenProtector``.
    public var doNotTranslate: [String]
    /// A model per action (`FR-CFG-02`).
    public var models: [Action: String]
    public var timeoutSeconds: Double
    public var retentionDays: Int
    /// Below this, detection is ambiguous and the user is asked rather than
    /// guessed at (`FR-TRN-03`).
    public var detectionConfidenceFloor: Double
    /// Selections shorter than this are never guessed at (`FR-TRN-03`).
    /// Measured in non-whitespace characters -- see ``LanguageDetector``.
    public var minimumLengthForDetection: Int

    public init(
        languages: [LanguageConfig],
        profiles: [AudienceProfile],
        glossary: Glossary,
        doNotTranslate: [String],
        models: [Action: String],
        timeoutSeconds: Double,
        retentionDays: Int,
        detectionConfidenceFloor: Double,
        minimumLengthForDetection: Int
    ) {
        self.languages = languages
        self.profiles = profiles
        self.glossary = glossary
        self.doNotTranslate = doNotTranslate
        self.models = models
        self.timeoutSeconds = timeoutSeconds
        self.retentionDays = retentionDays
        self.detectionConfidenceFloor = detectionConfidenceFloor
        self.minimumLengthForDetection = minimumLengthForDetection
    }

    public var enabledLanguages: [LanguageConfig] {
        languages.filter(\.enabled)
    }

    public func language(for code: LanguageCode) -> LanguageConfig? {
        languages.first { $0.code == code }
    }

    public func profile(id: String) -> AudienceProfile? {
        profiles.first { $0.id == id }
    }
}

extension Configuration {

    /// The model a fresh install points every action at.
    ///
    /// A starting point, not a recommendation: `FR-ONB-01` walks the user
    /// through choosing one, and `FR-EVL-01`'s harness exists to decide which is
    /// actually good. Named here so the first run has something to try.
    public static let defaultModel = "llama3.1:8b"

    public static let `default` = Configuration(
        languages: LanguageConfig.shippedDefaults,
        profiles: AudienceProfile.shippedDefaults,
        glossary: Glossary(),
        doNotTranslate: [],
        models: Dictionary(uniqueKeysWithValues: Action.allCases.map { ($0, defaultModel) }),
        timeoutSeconds: 60,
        retentionDays: 90,
        detectionConfidenceFloor: 0.65,
        minimumLengthForDetection: 12
    )
}
