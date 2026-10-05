import Foundation

public enum CorrectionOutcome: Sendable, Equatable {
    case corrected(CorrectionResult)
    case failed(EvalFailure)
}

public struct CorrectionScore: Sendable, Equatable, Codable {
    public let caseID: String
    public let failure: EvalFailure?
    public let expectedFixes: Int
    /// The `wrong` of every fix not found.
    public let missedFixes: [String]
    public let overCorrectedWords: Int
    public let originalWords: Int
    public let guardViolations: [String]
    public let categoryMatches: Int
    public let unexplainedFixes: Int
    /// Nil unless the case is clean.
    public let cleanPassed: Bool?
    public let warnings: Int

    public var foundFixes: Int { expectedFixes - missedFixes.count }

    /// Nil for a case that expects no fixes (a clean or guard-only case).
    public var recall: Double? {
        guard expectedFixes > 0 else { return nil }
        return Double(foundFixes) / Double(expectedFixes)
    }
}

/// One correction scored against its case (spec 2026-09-30, section 4.2).
public enum CorrectionScorer {

    public static func score(_ testCase: CorrectionCase, outcome: CorrectionOutcome) -> CorrectionScore {
        switch outcome {
        case .failed(let failure):
            return CorrectionScore(
                caseID: testCase.id, failure: failure, expectedFixes: testCase.fixes.count,
                missedFixes: testCase.fixes.map(\.wrong), overCorrectedWords: 0,
                originalWords: TextSearch.wordCount(testCase.text), guardViolations: [],
                categoryMatches: 0, unexplainedFixes: 0,
                cleanPassed: cleanVerdict(testCase, passed: false), warnings: 0)
        case .corrected(let result):
            return score(testCase, result)
        }
    }

    private static func score(_ testCase: CorrectionCase, _ result: CorrectionResult) -> CorrectionScore {
        let corrected = result.corrected.value
        let found = testCase.fixes.filter { isFound($0, in: corrected) }
        let missed = testCase.fixes.filter { !isFound($0, in: corrected) }
        let categories = categoryCheck(found: found, original: testCase.text, errors: result.errors)
        let unchanged = result.hasNoErrors && corrected == testCase.text
        return CorrectionScore(
            caseID: testCase.id, failure: nil, expectedFixes: testCase.fixes.count,
            missedFixes: missed.map(\.wrong),
            overCorrectedWords: overCorrectedWords(in: result.diff, original: testCase.text, fixes: testCase.fixes),
            originalWords: TextSearch.wordCount(testCase.text),
            guardViolations: testCase.mustNot.filter { corrected.contains($0) },
            categoryMatches: categories.matches, unexplainedFixes: categories.unexplained,
            cleanPassed: cleanVerdict(testCase, passed: unchanged), warnings: result.warnings.count)
    }

    private static func cleanVerdict(_ testCase: CorrectionCase, passed: Bool) -> Bool? {
        guard testCase.clean else { return nil }
        return passed
    }

    /// `wrong` is gone and some alternative is present, both as whole words.
    static func isFound(_ fix: ExpectedFix, in corrected: String) -> Bool {
        !TextSearch.contains(fix.wrong, in: corrected)
            && fix.right.contains { TextSearch.contains($0, in: corrected) }
    }

    /// Words changed outside every expected fix's span.
    static func overCorrectedWords(in segments: [DiffSegment], original: String, fixes: [ExpectedFix]) -> Int {
        let spans = fixes
            .flatMap { TextSearch.occurrences(of: $0.wrong, in: original, wholeWords: true) }
            .map { ($0.lowerBound - 1)..<($0.upperBound + 1) }
        var position = 0
        var count = 0
        for segment in segments {
            switch segment {
            case .same(let text):
                position += text.count
            case .removed(let text):
                let covered = position..<(position + text.count)
                if !spans.contains(where: { $0.overlaps(covered) }) { count += TextSearch.wordCount(text) }
                position += text.count
            case .added(let text):
                if !spans.contains(where: { $0.contains(position) }) { count += TextSearch.wordCount(text) }
            }
        }
        return count
    }

    /// For each found fix: is it explained by an overlapping item, and does
    /// one such item carry the expected category?
    static func categoryCheck(
        found: [ExpectedFix], original: String, errors: [CorrectionError]
    ) -> (matches: Int, unexplained: Int) {
        var matches = 0
        var unexplained = 0
        for fix in found {
            let fixRanges = TextSearch.occurrences(of: fix.wrong, in: original, wholeWords: true)
            let overlapping = errors.filter { error in
                TextSearch.occurrences(of: error.original, in: original, wholeWords: false)
                    .contains { range in fixRanges.contains { $0.overlaps(range) } }
            }
            if overlapping.isEmpty {
                unexplained += 1
            } else if overlapping.contains(where: { $0.category == fix.category }) {
                matches += 1
            }
        }
        return (matches, unexplained)
    }
}
