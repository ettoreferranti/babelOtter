import Foundation
import NaturalLanguage

/// Anything that can guess a language and say how sure it is.
///
/// The seam exists so the *policy* below can be tested deterministically.
/// `NLLanguageRecognizer` is a system ML model whose exact confidences move
/// between OS versions, and this project builds on Swift 6.4 / macOS 27 locally
/// while CI runs macOS 15 -- asserting `0.83 >= floor` against the live model
/// would produce a test that passes on one machine and fails on the other.
public protocol LanguageRecognizing: Sendable {
    func hypotheses(for text: String) -> [LanguageCode: Double]
}

/// Why detection declined to commit.
public enum AmbiguityReason: Sendable, Equatable {
    /// Too little text to be worth guessing at (`FR-TRN-03`).
    case tooShort(length: Int, minimum: Int)
    /// A best guess exists but is not trusted; carried so a picker can
    /// pre-select it.
    case belowFloor(best: LanguageCode, confidence: Double, floor: Double)
    /// The recognizer offered nothing at all.
    case noHypothesis
}

public enum Detection: Sendable, Equatable {
    case confident(LanguageCode, confidence: Double)
    case ambiguous(AmbiguityReason)

    /// The language this detection points at, confident or not -- `nil` only when
    /// there is no guess to be had.
    public var languageCode: LanguageCode? {
        switch self {
        case .confident(let code, _): return code
        case .ambiguous(.belowFloor(let best, _, _)): return best
        case .ambiguous: return nil
        }
    }
}

/// On-device language detection with an explicit confidence floor.
///
/// `FR-TRN-01` and `FR-TRN-03`. Detection runs through `NaturalLanguage`, which
/// is on-device and opens no connection -- the same reason the rest of this
/// package can promise NFR-P1.
public struct LanguageDetector: Sendable {

    let recognizer: any LanguageRecognizing
    private let floor: Double
    private let minimumLength: Int

    public init(recognizer: any LanguageRecognizing, floor: Double, minimumLength: Int) {
        self.recognizer = recognizer
        self.floor = floor
        self.minimumLength = minimumLength
    }

    /// Builds a detector from configuration, so the floor and minimum are the
    /// user's rather than this type's. Without an injected recognizer, the
    /// system one is screened (#81): see `ScreenedRecognizer`.
    public init(configuration: Configuration, recognizer: (any LanguageRecognizing)? = nil) {
        let enabled = configuration.enabledLanguages.map(\.code)
        let screened = ScreenedRecognizer(
            open: NaturalLanguageRecognizer(),
            constrained: NaturalLanguageRecognizer(constraints: enabled),
            enabled: enabled,
            floor: configuration.detectionConfidenceFloor)
        self.init(
            recognizer: recognizer ?? screened,
            floor: configuration.detectionConfidenceFloor,
            minimumLength: configuration.minimumLengthForDetection
        )
    }

    public func detect(_ text: String) -> Detection {
        // Measured in non-whitespace characters: a padded selection is exactly
        // the short-selection case FR-TRN-03 means, and counting the padding
        // would let "   hi   " past a minimum it should not clear.
        let length = text.count { !$0.isWhitespace }
        guard length >= minimumLength else {
            return .ambiguous(.tooShort(length: length, minimum: minimumLength))
        }

        let hypotheses = recognizer.hypotheses(for: text)
        // Sorted with an explicit tie-break rather than `max(by:)`. A dictionary
        // has no order, so on equal confidences `max` returns whichever the hash
        // order happened to put last -- a different answer between runs, for the
        // one input where the answer matters most. Ties break on the language
        // code so the same selection always resolves the same way.
        guard
            let best = hypotheses.sorted(by: { left, right in
                if left.value != right.value { return left.value > right.value }
                return left.key.rawValue < right.key.rawValue
            }).first
        else {
            return .ambiguous(.noHypothesis)
        }

        // `>=` and not `>`: a confidence exactly at the configured floor is
        // confident. Stated because a mutant flipping this must be killed, and
        // `exactlyAtFloor` sits precisely on the boundary to do it.
        guard best.value >= floor else {
            return .ambiguous(.belowFloor(best: best.key, confidence: best.value, floor: floor))
        }
        return .confident(best.key, confidence: best.value)
    }
}

/// Detection in two passes (#81). French and Italian are easily confused on
/// a short text, so the guess is made among the enabled languages only. But
/// a recognizer limited that way rescales its confidences: with English and
/// German enabled, an Italian sentence comes back as German, confidently, and
/// Correct would correct it as German. So the open recognizer goes first; a
/// confident guess outside the enabled languages stands, and is refused
/// downstream as before. Otherwise the constrained guess is used.
public struct ScreenedRecognizer: LanguageRecognizing {

    let open: any LanguageRecognizing
    let constrained: any LanguageRecognizing
    /// Base subtags: `de-ch` is enabled when `de` is detected.
    let enabled: [LanguageCode]
    let floor: Double

    public init(
        open: any LanguageRecognizing, constrained: any LanguageRecognizing,
        enabled: [LanguageCode], floor: Double
    ) {
        self.open = open
        self.constrained = constrained
        self.enabled = enabled.map(\.baseSubtag)
        self.floor = floor
    }

    public func hypotheses(for text: String) -> [LanguageCode: Double] {
        let wide = open.hypotheses(for: text)
        for (code, confidence) in wide where confidence >= floor {
            if !enabled.contains(code.baseSubtag) { return wide }
        }
        return constrained.hypotheses(for: text)
    }
}

/// `NLLanguageRecognizer`, on-device and offline.
public struct NaturalLanguageRecognizer: LanguageRecognizing {

    /// How many candidates to ask for. Two is enough to tell a clear winner from
    /// a coin toss, which is all the policy above needs.
    private let maximumHypotheses: Int

    /// The languages a guess is limited to, by base subtag (`de-ch` is `de`);
    /// empty means any language.
    let constraints: [LanguageCode]

    public init(maximumHypotheses: Int = 2, constraints: [LanguageCode] = []) {
        self.maximumHypotheses = maximumHypotheses
        self.constraints = constraints.map(\.baseSubtag)
    }

    public func hypotheses(for text: String) -> [LanguageCode: Double] {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = constraints.map { NLLanguage(rawValue: $0.rawValue) }
        recognizer.processString(text)
        let raw = recognizer.languageHypotheses(withMaximum: maximumHypotheses)
        return Dictionary(
            uniqueKeysWithValues: raw.map { (LanguageCode($0.key.rawValue), $0.value) })
    }
}
