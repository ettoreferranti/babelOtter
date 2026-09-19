import Foundation
import NaturalLanguage

/// Anything that can guess a language and say how sure it is.
///
/// The seam exists so the *policy* below can be tested deterministically.
/// `NLLanguageRecognizer` is a system ML model whose exact confidences move
/// between OS versions, and this project builds on Swift 6.4 / macOS 27 locally
/// while CI runs macOS 15 — asserting `0.83 >= floor` against the live model
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

    /// The language this detection points at, confident or not — `nil` only when
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
/// is on-device and opens no connection — the same reason the rest of this
/// package can promise NFR-P1.
public struct LanguageDetector: Sendable {

    private let recognizer: any LanguageRecognizing
    private let floor: Double
    private let minimumLength: Int

    public init(recognizer: any LanguageRecognizing, floor: Double, minimumLength: Int) {
        self.recognizer = recognizer
        self.floor = floor
        self.minimumLength = minimumLength
    }

    /// Builds a detector from configuration, so the floor and minimum are the
    /// user's rather than this type's.
    public init(configuration: Configuration, recognizer: any LanguageRecognizing = NaturalLanguageRecognizer()) {
        self.init(
            recognizer: recognizer,
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
        guard let best = hypotheses.max(by: { $0.value < $1.value }) else {
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

/// `NLLanguageRecognizer`, on-device and offline.
public struct NaturalLanguageRecognizer: LanguageRecognizing {

    /// How many candidates to ask for. Two is enough to tell a clear winner from
    /// a coin toss, which is all the policy above needs.
    private let maximumHypotheses: Int

    public init(maximumHypotheses: Int = 2) {
        self.maximumHypotheses = maximumHypotheses
    }

    public func hypotheses(for text: String) -> [LanguageCode: Double] {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let raw = recognizer.languageHypotheses(withMaximum: maximumHypotheses)
        return Dictionary(
            uniqueKeysWithValues: raw.map { (LanguageCode($0.key.rawValue), $0.value) })
    }
}
