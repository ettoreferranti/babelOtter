import Foundation

/// What the pipeline should do about direction.
public enum Resolution: Sendable, Equatable {
    /// Both ends known. `source` is the *configured* language, not the raw
    /// detection, so `de` resolves to the enabled `de-ch` and carries its rules.
    case resolved(source: LanguageCode, target: LanguageCode)
    /// Detected something real, but the user has not enabled it.
    case notEnabled(LanguageCode)
    /// More than one plausible other side — or none. Carries the candidates so a
    /// picker can offer them.
    case ambiguousPairing(candidates: [LanguageCode])
    /// Detection itself declined to commit; ask the user (`FR-TRN-03`).
    case needsUserChoice(AmbiguityReason)
}

/// Works out what to translate into, using only the configured languages.
///
/// `FR-LNG-01` and `FR-LNG-03`: no language code appears in this logic, so
/// adding French is a configuration edit. The test suite proves it by resolving
/// between two invented codes.
public struct TargetLanguageResolver: Sendable {

    public let languages: [LanguageConfig]

    public init(languages: [LanguageConfig]) {
        self.languages = languages
    }

    public init(configuration: Configuration) {
        self.init(languages: configuration.languages)
    }

    public func resolve(_ detection: Detection) -> Resolution {
        guard case .confident(let detected, _) = detection else {
            guard case .ambiguous(let reason) = detection else {
                return .ambiguousPairing(candidates: [])
            }
            return .needsUserChoice(reason)
        }

        let enabled = languages.filter(\.enabled)

        // Detection reports a language; configuration names a locale. `de` has
        // to find `de-CH`, or German never resolves at all.
        guard let source = enabled.first(where: { matches($0.code, detected) }) else {
            return .notEnabled(detected)
        }

        let others = enabled.map(\.code).filter { $0 != source.code }
        guard others.count == 1 else {
            return .ambiguousPairing(candidates: others)
        }
        return .resolved(source: source.code, target: others[0])
    }

    /// Equal outright, or equal once both are reduced to their base subtag.
    private func matches(_ configured: LanguageCode, _ detected: LanguageCode) -> Bool {
        configured == detected || configured.baseSubtag == detected.baseSubtag
    }
}
