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
/// fragment is German, as it was before #81. But a below-floor guess that
/// names another candidate (English, for Correct) is a real doubt, and the
/// user is asked; so is any case with several candidates.
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
            guard let code = configured(detected, among: enabled) else {
                return .notEnabled(detected)
            }
            if excludingMine {
                if code == mine { return .mine(code) }
            }
            return .known(code)
        }
        var candidates = enabled
        if excludingMine {
            candidates = others
        }
        if others.count == 1 {
            let assumed = others[0]
            guard case .ambiguous(.belowFloor(let best, _, _)) = detection else { return .known(assumed) }
            guard let guessed = configured(best, among: candidates) else { return .known(assumed) }
            if guessed == assumed { return .known(assumed) }
            return .ask(candidates)
        }
        return .ask(candidates)
    }

    /// The enabled language for a detected code: the exact code first, then
    /// the first with the same base subtag (`de` is `de-ch`).
    private static func configured(_ detected: LanguageCode, among enabled: [LanguageCode]) -> LanguageCode? {
        if enabled.contains(detected) { return detected }
        return enabled.first { $0.baseSubtag == detected.baseSubtag }
    }
}
