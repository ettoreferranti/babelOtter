import Foundation

/// A record's labels, as the History window shows them (#68). Names come
/// from the current configuration; an audience or language that has since
/// been removed shows its id instead.
public struct HistoryRow: Equatable, Sendable {

    public static let excerptLength = 80

    /// The action's name: "Translate".
    public let title: String
    /// "English -> Swiss Standard German" with a real arrow, or one language
    /// for actions that keep it.
    public let languages: String
    /// The audience's name; nil when the record has none (Explain).
    public let audience: String?
    /// The source application's name, else its bundle id.
    public let application: String?
    /// The source's first line with text, cut at `excerptLength` characters.
    public let excerpt: String

    public init(_ record: HistoryRecord, configuration: Configuration) {
        title = record.action.displayName
        var languages = Self.name(record.sourceLanguage, configuration)
        if let target = record.targetLanguage {
            languages += " \u{2192} " + Self.name(target, configuration)
        }
        self.languages = languages
        audience = record.profileID.map { configuration.profile(id: $0)?.name ?? $0 }
        application = record.sourceAppName ?? record.sourceBundleID
        excerpt = Self.excerpt(record.source.value)
    }

    private static func name(_ code: LanguageCode, _ configuration: Configuration) -> String {
        configuration.language(for: code)?.displayName ?? code.rawValue
    }

    private static func excerpt(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline)
        let line = lines.first { !$0.allSatisfy(\.isWhitespace) } ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.count > excerptLength {
            return String(trimmed.prefix(excerptLength)) + "..."
        }
        return trimmed
    }
}
