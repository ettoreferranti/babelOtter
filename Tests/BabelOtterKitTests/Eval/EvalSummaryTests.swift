import Testing

@testable import BabelOtterKit

private func correctionScore(
    expected: Int = 0, missed: Int = 0, over: Int = 0, words: Int = 10, guards: [String] = [],
    matches: Int = 0, unexplained: Int = 0, clean: Bool? = nil, warnings: Int = 0,
    failure: EvalFailure? = nil
) -> CorrectionScore {
    CorrectionScore(
        caseID: "c", failure: failure, expectedFixes: expected,
        missedFixes: Array(repeating: "w", count: missed), overCorrectedWords: over,
        originalWords: words, guardViolations: guards, categoryMatches: matches,
        unexplainedFixes: unexplained, cleanPassed: clean, warnings: warnings)
}

private func translationScore(
    esszett: Bool? = true, missing: [String] = [], debris: Bool = false, structure: Bool = true,
    chrF: Double = 50, failure: EvalFailure? = nil
) -> TranslationScore {
    TranslationScore(
        caseID: "t", failure: failure, esszettAbsent: esszett, missingTerms: missing,
        sentinelDebris: debris, structureKept: structure, chrF: chrF)
}

private func close(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 0.0001 }

@Suite("Eval: summaries and deltas")
struct EvalSummaryTests {

    private let scores = [
        correctionScore(expected: 2, missed: 1, over: 1, words: 10, matches: 1, warnings: 1),
        correctionScore(expected: 1, missed: 0, over: 0, words: 10, guards: ["Kollegin"], unexplained: 1),
        correctionScore(clean: true),
        correctionScore(expected: 1, missed: 1, over: 4, words: 5, failure: .timeout),
    ]

    @Test("correction metrics aggregate as specified")
    func correction() {
        let summary = CorrectionSummary(model: "m", scores: scores, seconds: [1, 3, 2, 10])
        #expect(summary.cases == 4)
        #expect(close(summary.meanRecall, 0.5))
        #expect(summary.overCorrectedWords == 1)
        #expect(close(summary.overCorrectionRate, 1.0 / 30.0))
        #expect(summary.guardViolations == 1)
        #expect(close(summary.categoryAccuracy, 0.5))
        #expect(close(summary.cleanPassRate, 1))
        #expect(summary.failures == ["timeout": 1])
        #expect(summary.warnings == 1)
        #expect(summary.latency == Latency(median: 2.5, max: 10))
    }

    @Test("rates with nothing to measure are 0")
    func emptyRates() {
        let summary = CorrectionSummary(model: "m", scores: [], seconds: [])
        #expect(summary.meanRecall == 0)
        #expect(summary.overCorrectionRate == 0)
        #expect(summary.categoryAccuracy == 0)
        #expect(summary.cleanPassRate == 0)
        #expect(summary.latency == Latency(median: 0, max: 0))
    }

    @Test("latency median of an odd count is the middle value")
    func oddMedian() {
        #expect(Latency(seconds: [5, 1, 3]) == Latency(median: 3, max: 5))
    }

    @Test("translation metrics aggregate as specified")
    func translation() {
        let summary = TranslationSummary(model: "m", scores: [
            translationScore(esszett: true, chrF: 80),
            translationScore(esszett: nil, missing: ["X"], structure: false, chrF: 40),
            translationScore(esszett: false, debris: true, chrF: 0, failure: .other),
        ], seconds: [2, 4, 6])
        #expect(summary.cases == 3)
        #expect(close(summary.esszettPassRate, 0.5))
        #expect(close(summary.termPassRate, 1.0 / 3.0))
        #expect(close(summary.structurePassRate, 2.0 / 3.0))
        #expect(close(summary.meanChrF, 40))
        #expect(summary.failures == ["other": 1])
        #expect(summary.latency == Latency(median: 4, max: 6))
    }

    @Test("metrics are listed in a fixed order with their direction")
    func metricNames() {
        let correction = CorrectionSummary(model: "m", scores: scores, seconds: [1])
        #expect(correction.metrics.map(\.name) == [
            "recall", "over-correction", "over-corrected words", "guard violations",
            "category accuracy", "clean pass", "failures", "warnings", "latency median", "latency max",
        ])
        #expect(correction.metrics.first?.higherIsBetter == true)
        #expect(correction.metrics[1].higherIsBetter == false)
        #expect(correction.metrics.first(where: { $0.name == "failures" })?.value == 1)
        let translation = TranslationSummary(model: "m", scores: [], seconds: [])
        #expect(translation.metrics.map(\.name) == [
            "no eszett", "terms kept", "structure kept", "chrF", "failures", "latency median", "latency max",
        ])
    }

    @Test("a delta pairs metrics by name and skips ones the earlier run lacks")
    func delta() {
        let before = CorrectionSummary(model: "m", scores: [correctionScore(expected: 2, missed: 2)], seconds: [1])
        let after = CorrectionSummary(model: "m", scores: [correctionScore(expected: 2, missed: 0)], seconds: [3])
        let deltas = after.delta(from: before)
        let recall = deltas.first { $0.name == "recall" }
        #expect(recall?.before == 0)
        #expect(recall?.after == 1)
        #expect(recall?.change == 1)
        #expect(deltas.first { $0.name == "latency median" }?.change == 2)
        #expect(deltas.count == after.metrics.count)

        let translation = TranslationSummary(model: "m", scores: [], seconds: [])
        let across = after.delta(from: translation)
        #expect(across.map(\.name) == ["failures", "latency median", "latency max"])
    }
}
