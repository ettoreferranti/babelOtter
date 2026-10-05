import Foundation
import Testing

@testable import BabelOtterKit

private func correctionRecord(_ model: String, _ caseID: String, run: Int = 1, seconds: Double = 1, warnings: Int = 0) -> CaseRecord {
    let score = CorrectionScore(
        caseID: caseID, failure: nil, expectedFixes: 1, missedFixes: [], overCorrectedWords: 0,
        originalWords: 4, guardViolations: [], categoryMatches: 1, unexplainedFixes: 0,
        cleanPassed: nil, warnings: warnings)
    return CaseRecord(
        model: model, caseID: caseID, run: run, seconds: seconds, output: nil, failureDetail: nil,
        correction: score, translation: nil)
}

private func translationRecord(_ model: String, _ caseID: String, run: Int = 1, chrF: Double = 50) -> CaseRecord {
    let score = TranslationScore(
        caseID: caseID, failure: nil, esszettAbsent: true, missingTerms: [], sentinelDebris: false,
        structureKept: true, chrF: chrF)
    return CaseRecord(
        model: model, caseID: caseID, run: run, seconds: 2, output: nil, failureDetail: nil,
        correction: nil, translation: score)
}

private func savedRun(repeatCount: Int = 1, _ records: [CaseRecord]) -> EvalRun {
    EvalRun(
        startedAt: Date(timeIntervalSince1970: 0), commit: "old", repeatCount: repeatCount,
        correction: [], translation: [], records: records)
}

@Suite("Eval: the saved run")
struct EvalRunTests {

    @Test("a run survives encoding and decoding")
    func roundTrip() throws {
        let score = CorrectionScore(
            caseID: "c", failure: nil, expectedFixes: 1, missedFixes: [], overCorrectedWords: 0,
            originalWords: 4, guardViolations: [], categoryMatches: 1, unexplainedFixes: 0,
            cleanPassed: nil, warnings: 0)
        let run = EvalRun(
            startedAt: Date(timeIntervalSince1970: 1_790_000_000), commit: "abc1234", repeatCount: 2,
            correction: [CorrectionSummary(model: "m", scores: [score, score], seconds: [2, 2], runs: 2)],
            translation: [],
            records: [CaseRecord(
                model: "m", caseID: "c", run: 1, seconds: 2, output: "Ich bin jetzt da.",
                failureDetail: nil, correction: score, translation: nil)])
        #expect(try EvalRun.decode(run.encoded()) == run)
    }

    @Test("a run saved before repeats were recorded reads as one run")
    func legacyRun() throws {
        let json = """
            {"commit": "abc1234", "startedAt": "2026-10-05T07:55:00Z", "records": [],
             "correction": [{"model": "m", "cases": 1, "meanRecall": 1, "overCorrectedWords": 2,
               "overCorrectionRate": 0.1, "guardViolations": 0, "categoryAccuracy": 1,
               "cleanPassRate": 0, "failures": {}, "warnings": 3, "latency": {"median": 1, "max": 1}}],
             "translation": [{"model": "m", "cases": 1, "esszettPassRate": 1, "termPassRate": 1,
               "structurePassRate": 1, "meanChrF": 50, "failures": {"other": 1},
               "latency": {"median": 1, "max": 1}}]}
            """
        let run = try EvalRun.decode(Data(json.utf8))
        #expect(run.repeatCount == 1)
        #expect(run.correction.first?.runs == 1)
        #expect(run.correction.first?.metrics.first { $0.name == "warnings" }?.value == 3)
        #expect(run.translation.first?.runs == 1)
        #expect(run.translation.first?.metrics.first { $0.name == "failures" }?.value == 1)
    }

    @Test("the saved results from before repeats still decode")
    func savedResults() throws {
        let directory = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../evals/results").standardized.path
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        for file in files where file.hasSuffix(".json") {
            let data = try #require(FileManager.default.contents(atPath: directory + "/" + file))
            #expect(throws: Never.self, "\(file)") { try EvalRun.decode(data) }
        }
    }

    @Test("the file name is the start time and the commit")
    func fileName() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21 14:13:20 UTC
        #expect(EvalRun.fileName(startedAt: date, commit: "abc1234", timeZone: utc)
            == "2026-09-21-141320-abc1234.json")
    }

    @Test("a run fails as a whole only when every case failed")
    func everyCaseFailed() {
        let failedCorrection = CaseRecord(
            model: "m", caseID: "a", run: 1, seconds: 1, output: nil, failureDetail: "down",
            correction: CorrectionScore(
                caseID: "a", failure: .unreachable, expectedFixes: 1, missedFixes: ["x"],
                overCorrectedWords: 0, originalWords: 4, guardViolations: [], categoryMatches: 0,
                unexplainedFixes: 0, cleanPassed: nil, warnings: 0),
            translation: nil)
        let failedTranslation = CaseRecord(
            model: "m", caseID: "t", run: 1, seconds: 1, output: nil, failureDetail: "down",
            correction: nil,
            translation: TranslationScore(
                caseID: "t", failure: .unreachable, esszettAbsent: nil, missingTerms: [],
                sentinelDebris: false, structureKept: false, chrF: 0))
        #expect(savedRun([failedCorrection, failedTranslation]).everyCaseFailed)
        #expect(!savedRun([failedCorrection, translationRecord("m", "t")]).everyCaseFailed)
        #expect(!savedRun([correctionRecord("m", "a"), failedTranslation]).everyCaseFailed)
        #expect(!savedRun([]).everyCaseFailed)
    }

    @Test("a baseline is rebuilt over only the cases of the current run")
    func restricted() {
        let baseline = savedRun(repeatCount: 2, [
            correctionRecord("m", "a", run: 1, seconds: 1, warnings: 1),
            correctionRecord("m", "b", run: 1, seconds: 9, warnings: 5),
            translationRecord("m", "t", run: 1, chrF: 40),
            translationRecord("m", "u", run: 1, chrF: 0),
            correctionRecord("m", "a", run: 2, seconds: 3, warnings: 1),
            correctionRecord("m", "b", run: 2, seconds: 9, warnings: 5),
            translationRecord("m", "t", run: 2, chrF: 60),
            translationRecord("m", "u", run: 2, chrF: 0),
        ])
        let current = [correctionRecord("m", "a"), translationRecord("m", "t")]
        let rebuilt = baseline.comparable(to: current)
        let scoreA = correctionRecord("m", "a", warnings: 1).correction
        #expect(rebuilt.correction == [CorrectionSummary(
            model: "m", scores: [scoreA, scoreA].compactMap { $0 }, seconds: [1, 3], runs: 2)])
        #expect(rebuilt.correction.first?.metrics.first { $0.name == "warnings" }?.value == 1)
        #expect(rebuilt.correction.first?.latency == Latency(median: 2, max: 3))
        #expect(rebuilt.translation.first?.meanChrF == 50)
        #expect(rebuilt.translation.first?.runs == 2)
        #expect(rebuilt.missing.isEmpty)
    }

    @Test("current cases the baseline lacks are named, per model")
    func missingCase() {
        let baseline = savedRun([correctionRecord("m", "a"), correctionRecord("n", "a")])
        let current = [
            correctionRecord("m", "a"), correctionRecord("m", "new"), translationRecord("m", "t"),
            correctionRecord("n", "a"),
        ]
        let rebuilt = baseline.comparable(to: current)
        #expect(rebuilt.missing == ["m": ["new", "t"]])
        #expect(rebuilt.correction.map(\.model) == ["m", "n"])
        #expect(rebuilt.correction.map(\.cases) == [1, 1])
        #expect(rebuilt.translation.isEmpty)
    }

    @Test("a model the baseline lacks gets no baseline summary and all its cases are named")
    func missingModel() {
        let baseline = savedRun([correctionRecord("m", "a")])
        let current = [correctionRecord("m", "a"), correctionRecord("x", "a"), correctionRecord("x", "a", run: 2)]
        let rebuilt = baseline.comparable(to: current)
        #expect(rebuilt.correction.map(\.model) == ["m"])
        #expect(rebuilt.missing == ["x": ["a"]])
    }
}
