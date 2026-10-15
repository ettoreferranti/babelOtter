import Foundation

/// What a translation is told about its audience (#52).
public enum AudienceRequest: Sendable, Equatable {
    /// Write for this audience.
    case fixed(AudienceProfile)
    /// Choose from `profiles` the audience the text addresses and write for
    /// it; `fallback` when the text gives no clear sign.
    case infer(profiles: [AudienceProfile], fallback: AudienceProfile)
}

/// Reads the model's `detected_audience` against the configured audiences.
public enum AudienceInference {

    /// What the prompt asks the model to answer when the text gives no sign.
    public static let unclear = "unclear"

    /// The configured audience the model named: by id first, then by name,
    /// ignoring case and surrounding space. Nil means "use the fallback":
    /// no answer, `unclear`, or a name that is not configured.
    public static func match(_ detected: String?, in profiles: [AudienceProfile]) -> AudienceProfile? {
        guard let detected else { return nil }
        let wanted = detected.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if wanted.isEmpty { return nil }
        for profile in profiles where profile.id.lowercased() == wanted {
            return profile
        }
        for profile in profiles where profile.name.lowercased() == wanted {
            return profile
        }
        return nil
    }
}
