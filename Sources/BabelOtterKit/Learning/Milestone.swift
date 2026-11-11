import Foundation

/// Something worth marking on the way (#136). Each is earned once; a
/// "tamed" one once per category and language (by base code).
public enum Milestone: Sendable, Hashable, Codable {
    /// The first learning action.
    case firstSteps
    /// That many words corrected in total.
    case words(Int)
    /// That many texts explained.
    case explanations(Int)
    /// A correction of `LearningRules.cleanTextWords` or more with no error.
    case cleanText
    /// The category's rate at least halved over 30 days.
    case tamed(ErrorCategory, LanguageCode)
    /// That many weeks in a row with the goal met.
    case streak(Int)

    public static let wordSteps = [1_000, 5_000, 10_000]
    public static let explanationSteps = [10, 50]
    public static let streakSteps = [4, 12]

    /// As the popup and Progress name it; `languages` gives a tamed one's
    /// language its display name.
    public func title(languages: [LanguageConfig]) -> String {
        switch self {
        case .firstSteps:
            return "First steps"
        case .words(let count):
            return "\(Self.grouped(count)) words"
        case .explanations(let count):
            return "\(count) explanations"
        case .cleanText:
            return "Clean text"
        case .tamed(let category, let language):
            return "\(category.displayName) tamed in \(Self.name(of: language, in: languages))"
        case .streak(let weeks):
            return "\(weeks) weeks in a row"
        }
    }

    /// The configured language sharing the code's base ("de" finds
    /// "de-ch"), else the code itself.
    public static func name(of code: LanguageCode, in languages: [LanguageConfig]) -> String {
        for language in languages where language.code.baseSubtag == code.baseSubtag {
            return language.displayName
        }
        return code.rawValue
    }

    /// "1,000": the same in every locale, as the titles are English.
    static func grouped(_ number: Int) -> String {
        if number < 1_000 { return String(number) }
        let rest = String(number % 1_000)
        let zeros = String(repeating: "0", count: 3 - rest.count)
        return grouped(number / 1_000) + "," + zeros + rest
    }
}
