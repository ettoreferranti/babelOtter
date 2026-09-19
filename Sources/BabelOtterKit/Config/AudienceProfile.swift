import Foundation

/// How the writer addresses the reader.
///
/// Modelled as a named axis rather than a `Bool` because `FR-PRO-01` treats
/// register as one of the things a profile *carries*, and because German's
/// Sie/du split is not the only register distinction a later language might
/// need. The raw values are the pronouns themselves, so the value can be dropped
/// into a prompt without a translation table.
public enum Register: String, Sendable, Codable, CaseIterable {
    case formal = "Sie"
    case informal = "du"
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
    /// entry. Optional — an empty array emits no prompt section.
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
