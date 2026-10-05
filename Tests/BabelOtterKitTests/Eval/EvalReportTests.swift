import Testing

@testable import BabelOtterKit

private func correctionScore(expected: Int, missed: [String] = [], guards: [String] = [],
                             clean: Bool? = nil, failure: EvalFailure? = nil) -> CorrectionScore {
    CorrectionScore(
        caseID: "c", failure: failure, expectedFixes: expected, missedFixes: missed,
        overCorrectedWords: 0, originalWords: 10, guardViolations: guards, categoryMatches: 0,
        unexplainedFixes: 0, cleanPassed: clean, warnings: 0)
}

@Suite("Eval: the report")
struct EvalReportTests {

    @Test("values and changes are formatted by kind", arguments: [
        (0.82, MetricKind.rate, "82.0%", "+82.0pp"),
        (3.0, MetricKind.count, "3", "+3"),
        (6.25, MetricKind.seconds, "6.2s", "+6.2s"),
        (54.31, MetricKind.score, "54.3", "+54.3"),
    ])
    func formatting(value: Double, kind: MetricKind, formatted: String, change: String) {
        #expect(EvalReport.format(value, kind) == formatted)
        #expect(EvalReport.signedChange(value, kind) == change)
        #expect(EvalReport.signedChange(-value, kind).hasPrefix("-"))
    }

    @Test("a count that is not whole shows one decimal", arguments: [
        (0.7, "0.7", "+0.7"),
        (2.0 / 3.0, "0.7", "+0.7"),
        (2.0, "2", "+2"),
        (-1.0, "-1", "-1"),
        (-0.5, "-0.5", "-0.5"),
        (1.04, "1", "+1"),
    ])
    func fractionalCount(value: Double, formatted: String, change: String) {
        #expect(EvalReport.format(value, .count) == formatted)
        #expect(EvalReport.signedChange(value, .count) == change)
    }

    @Test("no change in a count is +0")
    func zeroCountChange() {
        #expect(EvalReport.signedChange(0, .count) == "+0")
        #expect(EvalReport.signedChange(-0.01, .count) == "+0")
    }

    @Test("repeated misses are listed once with the runs they occurred in")
    func collapsedMisses() {
        let runs = [["m  a: x", "m  b: y"], ["m  b: y", "m  c: z"], ["m  b: y"]]
        #expect(EvalReport.collapsedMisses(runs) == [
            "m  a: x (1/3 runs)", "m  b: y (3/3 runs)", "m  c: z (1/3 runs)",
        ])
        #expect(EvalReport.collapsedMisses([["m  a: x", "m  b: y"]]) == ["m  a: x", "m  b: y"])
        #expect(EvalReport.collapsedMisses([[], []]).isEmpty)
        #expect(EvalReport.collapsedMisses([["m  a: x", "m  a: x"], []]) == ["m  a: x (1/2 runs)"])
    }

    @Test("the table has a row per metric and a column per model")
    func table() {
        let a = CorrectionSummary(model: "alpha", scores: [correctionScore(expected: 2, missed: ["x"])], seconds: [1])
        let b = CorrectionSummary(model: "beta", scores: [correctionScore(expected: 2)], seconds: [2])
        let lines = EvalReport.table("Correction", [a, b], baseline: []).split(separator: "\n").map(String.init)
        #expect(lines[0] == "Correction")
        #expect(lines[1].hasPrefix("metric"))
        #expect(lines[1].contains("alpha") && lines[1].contains("beta"))
        let recall = lines.first { $0.hasPrefix("recall ") }
        #expect(recall?.contains("50.0%") == true)
        #expect(recall?.contains("100.0%") == true)
        #expect(lines.count == 2 + a.metrics.count)
    }

    @Test("a baseline adds changes only for the models it has")
    func baseline() {
        let before = CorrectionSummary(model: "alpha", scores: [correctionScore(expected: 2, missed: ["x", "y"])], seconds: [1])
        let alpha = CorrectionSummary(model: "alpha", scores: [correctionScore(expected: 2, missed: ["x"])], seconds: [1])
        let gamma = CorrectionSummary(model: "gamma", scores: [correctionScore(expected: 2)], seconds: [1])
        let text = EvalReport.table("Correction", [alpha, gamma], baseline: [before])
        let recall = text.split(separator: "\n").first { $0.hasPrefix("recall ") }.map(String.init)
        #expect(recall?.contains("50.0% (+50.0pp)") == true)
        #expect(recall?.contains("100.0% (") == false)
    }

    @Test("an empty summary list renders nothing")
    func empty() {
        #expect(EvalReport.table("Correction", [CorrectionSummary](), baseline: []).isEmpty)
    }

    @Test("correction misses name each missed fix, guard and clean failure")
    func correctionMisses() {
        let theCase = CorrectionCase(
            id: "jetz", text: "Ich bin jetz da.", profileID: "colleagues", terms: [],
            fixes: [ExpectedFix(wrong: "jetz", right: ["jetzt"], category: .spelling)],
            mustNot: ["Kollegin"], clean: false)
        let lines = EvalReport.correctionMisses(
            model: "m", testCase: theCase,
            score: correctionScore(expected: 1, missed: ["jetz"], guards: ["Kollegin"]))
        #expect(lines == [
            #"m  jetz: missed "jetz" (expected "jetzt")"#,
            #"m  jetz: must not contain "Kollegin""#,
        ])
        let clean = CorrectionCase(id: "ok", text: "Gut.", profileID: "colleagues", terms: [], fixes: [], mustNot: [], clean: true)
        #expect(EvalReport.correctionMisses(model: "m", testCase: clean, score: correctionScore(expected: 0, clean: false))
            == ["m  ok: the clean text was changed or flagged"])
        #expect(EvalReport.correctionMisses(model: "m", testCase: clean, score: correctionScore(expected: 0, clean: true)).isEmpty)
        #expect(EvalReport.correctionMisses(model: "m", testCase: theCase, score: correctionScore(expected: 1, missed: ["jetz"], failure: .timeout))
            == ["m  jetz: failed (timeout)"])
    }

    @Test("translation misses name each failed check")
    func translationMisses() {
        let theCase = TranslationCase(
            id: "t", text: "- Hi Otterbach", direction: .englishToSwissGerman, profileID: "colleagues",
            terms: ["Otterbach"], reference: "- Hallo Otterbach")
        let bad = TranslationScore(
            caseID: "t", failure: nil, esszettAbsent: false, missingTerms: ["Otterbach"],
            sentinelDebris: true, structureKept: false, chrF: 10)
        #expect(EvalReport.translationMisses(model: "m", testCase: theCase, score: bad) == [
            "m  t: contains an eszett",
            #"m  t: term "Otterbach" not kept"#,
            "m  t: a placeholder was left in the output",
            "m  t: structure changed",
        ])
        let good = TranslationScore(
            caseID: "t", failure: nil, esszettAbsent: true, missingTerms: [],
            sentinelDebris: false, structureKept: true, chrF: 90)
        #expect(EvalReport.translationMisses(model: "m", testCase: theCase, score: good).isEmpty)
        let failed = TranslationScore(
            caseID: "t", failure: .other, esszettAbsent: false, missingTerms: ["Otterbach"],
            sentinelDebris: false, structureKept: false, chrF: 0)
        #expect(EvalReport.translationMisses(model: "m", testCase: theCase, score: failed) == ["m  t: failed (other)"])
    }
}
