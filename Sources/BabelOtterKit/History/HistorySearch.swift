import Foundation

/// What a history search matches (#68, `FR-HIS-02`): source or result text,
/// ignoring case and accents, the same in every locale. Both stores ask here,
/// so they cannot disagree.
public enum HistorySearch {

    /// The term as search uses it: trimmed of white space; nil when nothing
    /// is left, which means "every record".
    public static func normalized(_ term: String) -> String? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return trimmed
    }

    /// "uber" finds "Uber" with an umlaut, and "strasse" finds the spelling
    /// with an eszett: case folding turns it into "ss".
    public static func contains(_ text: String, _ term: String) -> Bool {
        text.range(
            of: term, options: [.caseInsensitive, .diacriticInsensitive],
            range: nil, locale: nil) != nil
    }

    /// Only the text is searched, not the audience, app or model.
    public static func matches(_ record: HistoryRecord, _ term: String) -> Bool {
        if contains(record.source.value, term) { return true }
        return contains(record.result.value, term)
    }
}
