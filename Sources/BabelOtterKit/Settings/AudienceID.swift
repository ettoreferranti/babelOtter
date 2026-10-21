import Foundation

/// An audience's id, made once from the name it was created with (#61).
///
/// Readable rather than a UUID: app memory and history refer to it, and
/// config.json is meant to be edited by hand (`FR-CFG-03`). It never
/// changes on rename.
public enum AudienceID {

    public static let fallback = "audience"
    /// More audiences than anyone keeps; past it the number is the count.
    static let numberLimit = 1_000

    /// "Behoerden" style: lowercased, accents dropped, "ss" for an eszett,
    /// anything else not a-z or 0-9 a single "-"; then "-2", "-3", ... when
    /// taken.
    public static func make(from name: String, taken: Set<String>) -> String {
        let base = slug(name)
        if !taken.contains(base) { return base }
        // A fixed bound, so no change to it can make the loop endless.
        for number in 2...numberLimit {
            let candidate = base + "-" + String(number)
            if !taken.contains(candidate) { return candidate }
        }
        // Over a thousand ids taken: one more than any of them can be.
        return base + "-" + String(numberLimit + taken.count)
    }

    static func slug(_ name: String) -> String {
        let folded = name.lowercased()
            .replacingOccurrences(of: "\u{00DF}", with: "ss")
            .folding(options: [.diacriticInsensitive], locale: nil)
        var slug = ""
        var pendingDash = false
        for scalar in folded.unicodeScalars {
            if isPlain(scalar) {
                if pendingDash { slug += "-" }
                pendingDash = false
                slug.unicodeScalars.append(scalar)
            } else if !slug.isEmpty {
                pendingDash = true
            }
        }
        if slug.isEmpty { return fallback }
        return slug
    }

    private static func isPlain(_ scalar: Unicode.Scalar) -> Bool {
        if ("a"..."z").contains(scalar) { return true }
        return ("0"..."9").contains(scalar)
    }
}
