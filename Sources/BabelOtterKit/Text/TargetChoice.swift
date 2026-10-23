import Foundation

/// Choosing a target with three or more languages (#81): which targets the
/// popup's header menu offers, whether it shows a menu at all, and the
/// remembered target per source in the form the app stores it.
///
/// Stored as `[String: String]`, source code to target code: language codes
/// only, never text.
public enum TargetChoice {

    /// The enabled languages other than `source`, in configuration order.
    public static func menuTargets(source: LanguageCode, configuration: Configuration) -> [LanguageCode] {
        configuration.enabledLanguages.map(\.code).filter { $0 != source }
    }

    /// A menu with three or more enabled languages; with two, the header
    /// keeps its Swap button.
    public static func usesMenu(configuration: Configuration) -> Bool {
        configuration.enabledLanguages.count > 2
    }

    /// The stored form read back; codes are normalised as any other.
    public static func memory(from stored: [String: String]) -> [LanguageCode: LanguageCode] {
        var memory: [LanguageCode: LanguageCode] = [:]
        for (source, target) in stored {
            memory[LanguageCode(source)] = LanguageCode(target)
        }
        return memory
    }

    /// The stored form with `target` remembered for `source`.
    public static func remembering(
        _ target: LanguageCode, for source: LanguageCode, in stored: [String: String]
    ) -> [String: String] {
        var updated = stored
        updated[source.rawValue] = target.rawValue
        return updated
    }
}
