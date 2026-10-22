import Foundation

/// How formally the writer addresses the reader (#110).
///
/// Only the level: how a language expresses it -- Sie/du, Lei/tu, or no
/// pronoun at all in English -- is that language's `AddressForms`, so an
/// audience means the same whichever language it is written in.
public enum Register: String, Sendable, CaseIterable, Codable {
    case formal
    case informal

    static let expected = "expected \"formal\" or \"informal\""

    /// "formal", for labels.
    public var word: String { rawValue }

    /// "a formal register", "an informal register", as a prompt says it
    /// for a language without forms.
    public var phrase: String {
        switch self {
        case .formal: return "a formal register"
        case .informal: return "an informal register"
        }
    }

    /// Also the values before #110, the German pronouns: "Sie", "du".
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let written = try container.decode(String.self)
        switch written.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "formal", "sie":
            self = .formal
        case "informal", "du":
            self = .informal
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: Self.expected))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A named bundle of register, tone guidance and glossary bias.
///
/// `FR-PRO-01`. The point of profiles is that addressing students, colleagues
/// and an administration are genuinely different registers rather than points on
/// a single formality slider, so each is a value the user can name and edit.
public struct AudienceProfile: Sendable, Equatable, Codable, Identifiable {

    /// A stable, readable identifier such as `"students"`.
    ///
    /// Deliberately not a `UUID`. `FR-PRO-06` remembers the last profile used
    /// per source application, which means this id is written into other files,
    /// and `FR-CFG-03` invites the user to hand-edit those files. A UUID would
    /// make that editing hostile.
    public let id: String
    public var name: String
    public var register: Register
    /// Free text describing how this audience is addressed, injected verbatim
    /// into the prompt by ``PromptBuilder``.
    public var toneGuidance: String
    /// Terms this audience prefers, nudging the model without a full glossary
    /// entry. Optional -- an empty array emits no prompt section.
    public var glossaryBias: [String]

    public init(
        id: String,
        name: String,
        register: Register,
        toneGuidance: String,
        glossaryBias: [String] = []
    ) {
        self.id = id
        self.name = name
        self.register = register
        self.toneGuidance = toneGuidance
        self.glossaryBias = glossaryBias
    }
}

extension AudienceProfile {

    /// "Students (Sie)" for a language with address forms, "Students
    /// (formal)" for one without, and the name alone before the language
    /// is known (#110).
    public func label(in language: LanguageConfig?) -> String {
        guard let language else { return name }
        guard let forms = language.addressForms else { return "\(name) (\(register.word))" }
        return "\(name) (\(forms.form(for: register)))"
    }

    public static let students = AudienceProfile(
        id: "students",
        name: "Students",
        register: .formal,
        toneGuidance:
            "Clear and encouraging. Explain rather than assume. Keep sentences short and "
            + "avoid administrative jargon."
    )

    public static let colleagues = AudienceProfile(
        id: "colleagues",
        name: "Colleagues",
        register: .informal,
        toneGuidance:
            "Collegial and direct. Assume shared context and domain vocabulary. Brevity is "
            + "courtesy."
    )

    public static let administration = AudienceProfile(
        id: "administration",
        name: "Administration",
        register: .formal,
        toneGuidance:
            "Precise and procedural. Name deadlines, references and responsibilities "
            + "explicitly. Neutral tone throughout."
    )

    public static let informal = AudienceProfile(
        id: "informal",
        name: "Informal",
        register: .informal,
        toneGuidance: "Warm and conversational. Contractions and everyday vocabulary are welcome."
    )

    /// The four profiles a fresh install ships with (`FR-PRO-02`).
    public static let shippedDefaults: [AudienceProfile] = [
        .students, .colleagues, .administration, .informal,
    ]
}
