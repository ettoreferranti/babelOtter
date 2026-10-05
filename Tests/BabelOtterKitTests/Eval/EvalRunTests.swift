import Foundation
import Testing

@testable import BabelOtterKit

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
        let date = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21 14:13 UTC
        #expect(EvalRun.fileName(startedAt: date, commit: "abc1234", timeZone: utc)
            == "2026-09-21-1413-abc1234.json")
    }
}
