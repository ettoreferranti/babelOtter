import Foundation

/// The language Correct or Explain works on, decided from a detection (#81).
public enum TextLanguageResolution: Sendable, Equatable {
    /// An enabled language, as configured (`de` detected is `de-ch`).
    case known(LanguageCode)
    /// My language, where it is not wanted: Explain explains into it.
    case mine(LanguageCode)
    /// Detected confidently, but not one of the enabled languages.
    case notEnabled(LanguageCode)
    /// Unsure, with more than one candidate: ask "Which language is this?".
    case ask([LanguageCode])
}

/// Correct and Explain read one language each (#81).
///
/// A confident detection names it. When detection is unsure -- too short,
/// below the floor -- and exactly one enabled language is not my language,
/// that one is assumed: with English and German on and English mine, a short
/// fragment is German, as it was before #81. Otherwise the user is asked.
public enum TextLanguage {

    /// `excludingMine`: Explain's case, where a text in my language is
    /// refused and my language is never offered.
    public static func resolve(
        _ detection: Detection, configuration: Configuration, excludingMine: Bool
    ) -> TextLanguageResolution {
        let mine = configuration.myLanguageCode
        let enabled = configuration.enabledLanguages.map(\.code)
        let others = enabled.filter { $0 != mine }

        if case .confident(let detected, _) = detection {
            guard let code = enabled.first(where: { matches($0, detected) }) else {
                return .notEnabled(detected)
            }
            if excludingMine {
                if code == mine { return .mine(code) }
            }
            return .known(code)
        }
        if others.count == 1 {
            return .known(others[0])
        }
        if excludingMine {
            return .ask(others)
        }
        return .ask(enabled)
    }

    /// Equal outright, or equal once both are reduced to their base subtag.
    private static func matches(_ configured: LanguageCode, _ detected: LanguageCode) -> Bool {
        configured == detected || configured.baseSubtag == detected.baseSubtag
    }
}
