import Foundation

public enum TranslationOutcome: Sendable, Equatable {
    /// The finished translation's text.
    case translated(String)
    case failed(EvalFailure)
}

public struct TranslationScore: Sendable, Equatable, Codable {
    public let caseID: String
    public let failure: EvalFailure?
    /// Nil when the target is not German.
    public let esszettAbsent: Bool?
    public let missingTerms: [String]
    public let sentinelDebris: Bool
    public let structureKept: Bool
    public let chrF: Double

    public var termsKept: Bool { failure == nil && missingTerms.isEmpty && !sentinelDebris }
}

/// One translation scored against its case (spec 2026-09-30, section 4.3).
public enum TranslationScorer {

    static let sentinelBrackets = ["\u{27E6}", "\u{27E7}"]

    public static func score(_ testCase: TranslationCase, outcome: TranslationOutcome) -> TranslationScore {
        switch outcome {
        case .failed(let failure):
            return TranslationScore(
                caseID: testCase.id, failure: failure,
                esszettAbsent: localeCheck(testCase, output: nil), missingTerms: testCase.terms,
                sentinelDebris: false, structureKept: false, chrF: 0)
        case .translated(let output):
            return TranslationScore(
                caseID: testCase.id, failure: nil,
                esszettAbsent: localeCheck(testCase, output: output),
                missingTerms: testCase.terms.filter { !output.contains($0) },
                sentinelDebris: sentinelBrackets.contains { output.contains($0) },
                structureKept: sameStructure(testCase.text, output),
                chrF: ChrF.score(hypothesis: output, reference: testCase.reference))
        }
    }

    /// Whether the output keeps the target's orthography rules (#81): no
    /// rule's pattern appears in it. For de-CH that is the eszett check, which
    /// is why the score keeps that name. Nil for a target without rules; a
    /// failed run (no output) fails it.
    private static func localeCheck(_ testCase: TranslationCase, output: String?) -> Bool? {
        let rules = testCase.direction.targetRules
        guard !rules.isEmpty else { return nil }
        guard let output else { return false }
        return !rules.contains { output.contains($0.replace) }
    }

    /// The same number of blocks and the same list markers, in order.
    static func sameStructure(_ source: String, _ output: String) -> Bool {
        let before = StructureExtractor.extract(source).skeleton
        let after = StructureExtractor.extract(output).skeleton
        return before.blockCount == after.blockCount && markers(before) == markers(after)
    }

    private static func markers(_ skeleton: Skeleton) -> [String] {
        skeleton.lines
            .map { $0.marker.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
