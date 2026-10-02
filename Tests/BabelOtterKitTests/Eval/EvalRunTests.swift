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
            startedAt: Date(timeIntervalSince1970: 1_790_000_000), commit: "abc1234",
            correction: [CorrectionSummary(model: "m", scores: [score], seconds: [2])],
            translation: [],
            records: [CaseRecord(
                model: "m", caseID: "c", run: 1, seconds: 2, output: "Ich bin jetzt da.",
                failureDetail: nil, correction: score, translation: nil)])
        #expect(try EvalRun.decode(run.encoded()) == run)
    }

    @Test("the file name is the start time and the commit")
    func fileName() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21 14:13 UTC
        #expect(EvalRun.fileName(startedAt: date, commit: "abc1234", timeZone: utc)
            == "2026-09-21-1413-abc1234.json")
    }
}
