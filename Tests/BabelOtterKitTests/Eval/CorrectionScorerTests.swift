import Foundation
import Testing

@testable import BabelOtterKit

private func fix(_ wrong: String, _ right: [String], _ category: ErrorCategory = .spelling) -> ExpectedFix {
    ExpectedFix(wrong: wrong, right: right, category: category)
}

private func testCase(
    _ text: String, fixes: [ExpectedFix] = [], mustNot: [String] = [], clean: Bool = false
) -> CorrectionCase {
    CorrectionCase(
        id: "case", text: text, profileID: "colleagues", terms: [], fixes: fixes,
        mustNot: mustNot, clean: clean)
}

private func item(_ original: String, _ category: ErrorCategory) -> CorrectionError {
    CorrectionError(
        original: original, corrected: "x", category: category, explanationEn: "because",
        severity: .error)
}

private func corrected(
    _ original: String, _ text: String, errors: [CorrectionError] = [],
    warnings: [String] = [], hasNoErrors: Bool = false
) -> CorrectionOutcome {
    .corrected(CorrectionResult(
        original: UserText(original), corrected: UserText(text), errors: errors, suggestions: [],
        diff: WordDiff.diff(original, text), warnings: warnings, hasNoErrors: hasNoErrors))
}

@Suite("Eval: a correction scored against its case")
struct CorrectionScorerTests {

    // MARK: Failures

    @Test("pipeline errors map to failure kinds")
    func failureMapping() {
        #expect(EvalFailure(CorrectionFailure.unreadableReply) == .unreadableReply)
        #expect(EvalFailure(CorrectionFailure.structureLost) == .structureLost)
        #expect(EvalFailure(CorrectionFailure.notGerman) == .notGerman)
        #expect(EvalFailure(CorrectionFailure.emptyResponse) == .emptyResponse)
        #expect(EvalFailure(TranslationError.emptyResponse) == .emptyResponse)
        #expect(EvalFailure(URLError(.timedOut)) == .timeout)
        #expect(EvalFailure(URLError(.cannotConnectToHost)) == .other)
        #expect(EvalFailure(TranslationError.languageNotConfigured(LanguageCode("fr"))) == .other)
    }

    @Test("a failed correction misses every fix and fails a clean case")
    func failedOutcome() {
        let failing = testCase("Ich bin jetz da.", fixes: [fix("jetz", ["jetzt"])])
        let score = CorrectionScorer.score(failing, outcome: .failed(.timeout))
        #expect(score.failure == .timeout)
        #expect(score.missedFixes == ["jetz"])
        #expect(score.recall == 0)
        #expect(score.cleanPassed == nil)
        #expect(score.originalWords == 4)

        let clean = CorrectionScorer.score(testCase("Alles gut.", clean: true), outcome: .failed(.other))
        #expect(clean.cleanPassed == false)
        #expect(clean.recall == nil)
    }

    // MARK: Recall

    @Test("a fix counts when wrong is gone and an alternative is present")
    func recallWithAlternatives() {
        let text = "Heute bin ich jetz sehr müde."
        let theCase = testCase(text, fixes: [
            fix("jetz", ["jetzt"]),
            fix("bin ich jetz", ["bin jetzt", "ich bin jetzt"], .wordOrder),
        ])
        let score = CorrectionScorer.score(theCase, outcome: corrected(text, "Heute bin jetzt sehr müde."))
        #expect(score.missedFixes.isEmpty)
        #expect(score.foundFixes == 2)
        #expect(score.recall == 1)
    }

    @Test("wrong gone without any right alternative is a miss")
    func wrongGoneRightAbsent() {
        let text = "Ich bin jetz da."
        let score = CorrectionScorer.score(
            testCase(text, fixes: [fix("jetz", ["jetzt"])]), outcome: corrected(text, "Ich bin nun da."))
        #expect(score.missedFixes == ["jetz"])
    }

    @Test("a right alternative present while wrong remains is a miss")
    func rightPresentWrongRemains() {
        let text = "Ich bin jetz da, jetz."
        let score = CorrectionScorer.score(
            testCase(text, fixes: [fix("jetz", ["jetzt"])]),
            outcome: corrected(text, "Ich bin jetzt da, jetz."))
        #expect(score.missedFixes == ["jetz"])
    }

    @Test("a wrong that is a prefix of its correction is still found")
    func prefixOfCorrection() {
        let text = "Ich bin jetz da."
        let score = CorrectionScorer.score(
            testCase(text, fixes: [fix("jetz", ["jetzt"])]), outcome: corrected(text, "Ich bin jetzt da."))
        #expect(score.recall == 1)
    }

    // MARK: Guards, clean cases, warnings

    @Test("a mustNot string in the output is a violation")
    func guards() {
        let text = "Ich habe mit der Kollege gesprochen."
        let theCase = testCase(text, fixes: [fix("der Kollege", ["dem Kollegen"], .grammaticalCase)],
                               mustNot: ["Kollegin"])
        let bad = CorrectionScorer.score(theCase, outcome: corrected(text, "Ich habe mit der Kollegin gesprochen."))
        #expect(bad.guardViolations == ["Kollegin"])
        let good = CorrectionScorer.score(theCase, outcome: corrected(text, "Ich habe mit dem Kollegen gesprochen."))
        #expect(good.guardViolations.isEmpty)
    }

    @Test("a clean case passes only unchanged and with no errors")
    func cleanCases() {
        let text = "Alles ist gut."
        let theCase = testCase(text, clean: true)
        #expect(CorrectionScorer.score(theCase, outcome: corrected(text, text, hasNoErrors: true)).cleanPassed == true)
        #expect(CorrectionScorer.score(theCase, outcome: corrected(text, text, hasNoErrors: false)).cleanPassed == false)
        #expect(CorrectionScorer.score(theCase, outcome: corrected(text, "Alles ist sehr gut.", hasNoErrors: true)).cleanPassed == false)
        let notClean = testCase("Ich bin jetz da.", fixes: [fix("jetz", ["jetzt"])])
        #expect(CorrectionScorer.score(notClean, outcome: corrected("Ich bin jetz da.", "Ich bin jetzt da.")).cleanPassed == nil)
    }

    @Test("warnings are counted")
    func warnings() {
        let text = "Ich bin jetz da."
        let score = CorrectionScorer.score(
            testCase(text, fixes: [fix("jetz", ["jetzt"])]),
            outcome: corrected(text, "Ich bin jetzt da.", warnings: ["one", "two"]))
        #expect(score.warnings == 2)
    }

    // MARK: Over-correction

    @Test("a change inside a fix span is not over-correction")
    func insideSpan() {
        let text = "Ich habe jetz Zeit."
        let score = CorrectionScorer.score(
            testCase(text, fixes: [fix("jetz", ["jetzt"])]), outcome: corrected(text, "Ich habe jetzt Zeit."))
        #expect(score.overCorrectedWords == 0)
        #expect(score.originalWords == 4)
    }

    @Test("a change outside every fix span counts its removed and added words")
    func outsideSpan() {
        let text = "Ich habe jetz Zeit."
        let score = CorrectionScorer.score(
            testCase(text, fixes: [fix("jetz", ["jetzt"])]), outcome: corrected(text, "Ich habe jetzt Ruhe."))
        // "Zeit" -> "Ruhe" is two words away from the fix: one removed, one added.
        // (A change right next to the fix, such as "habe" -> "hatte", sits in
        // its one-character widening and counts as inside, by design.)
        #expect(score.overCorrectedWords == 2)
    }

    @Test("an insertion at a fix's edge is inside; one character further is outside")
    func insertionAtEdge() {
        let fixes = [fix("jetz", ["jetzt"])]
        // "ab jetz cd": "jetz" is 3..<7, widened to 2..<8.
        let atEnd: [DiffSegment] = [.same("ab jetz"), .added(" nun"), .same(" cd")]
        #expect(CorrectionScorer.overCorrectedWords(in: atEnd, original: "ab jetz cd", fixes: fixes) == 0)
        let atStart: [DiffSegment] = [.same("ab "), .added("nun "), .same("jetz cd")]
        #expect(CorrectionScorer.overCorrectedWords(in: atStart, original: "ab jetz cd", fixes: fixes) == 0)
        let pastEdge: [DiffSegment] = [.same("ab jetz "), .added("nun "), .same("cd")]
        #expect(CorrectionScorer.overCorrectedWords(in: pastEdge, original: "ab jetz cd", fixes: fixes) == 1)
    }

    @Test("an addition after a removal sits where the removal ended")
    func additionAfterRemoval() {
        let fixes = [fix("jetz", ["jetzt"])]
        let replaced: [DiffSegment] = [.same("ab "), .removed("jetz"), .added("jetzt"), .same(" cd")]
        #expect(CorrectionScorer.overCorrectedWords(in: replaced, original: "ab jetz cd", fixes: fixes) == 0)
        let later: [DiffSegment] = [.removed("ab"), .added("xy"), .same(" jetz")]
        #expect(CorrectionScorer.overCorrectedWords(in: later, original: "ab jetz", fixes: fixes) == 1)
    }

    @Test("with no fixes, every changed word is over-correction")
    func noFixes() {
        let segments: [DiffSegment] = [.same("Alles "), .removed("ist"), .added("war"), .same(" gut.")]
        #expect(CorrectionScorer.overCorrectedWords(in: segments, original: "Alles ist gut.", fixes: []) == 2)
    }

    // MARK: Categories

    @Test("a found fix with an overlapping item of the right category matches")
    func categoryMatch() {
        let found = [fix("der Kollege", ["dem Kollegen"], .grammaticalCase)]
        let result = CorrectionScorer.categoryCheck(
            found: found, original: "mit der Kollege", errors: [item("der Kollege", .grammaticalCase)])
        #expect(result.matches == 1)
        #expect(result.unexplained == 0)
    }

    @Test("an overlapping item of another category is explained but not a match")
    func categoryMismatch() {
        let found = [fix("der Kollege", ["dem Kollegen"], .grammaticalCase)]
        let result = CorrectionScorer.categoryCheck(
            found: found, original: "mit der Kollege", errors: [item("Kollege", .gender)])
        #expect(result.matches == 0)
        #expect(result.unexplained == 0)
    }

    @Test("a found fix no item overlaps is unexplained")
    func unexplained() {
        let found = [fix("jetz", ["jetzt"])]
        let result = CorrectionScorer.categoryCheck(
            found: found, original: "Ich bin jetz da.", errors: [item("Ich", .spelling)])
        #expect(result.matches == 0)
        #expect(result.unexplained == 1)
    }

    @Test("an item inside a word overlaps it, as the eszett row does")
    func itemInsideWord() {
        let found = [fix("Stra\u{00DF}e", ["Strasse"])]
        let result = CorrectionScorer.categoryCheck(
            found: found, original: "Die Stra\u{00DF}e ist lang.", errors: [item("\u{00DF}", .spelling)])
        #expect(result.matches == 1)
    }

    @Test("the scorer reports category matches for found fixes only")
    func categoriesOnlyForFound() {
        let text = "Ich bin jetz da und mude."
        let theCase = testCase(text, fixes: [fix("jetz", ["jetzt"]), fix("mude", ["müde"])])
        let score = CorrectionScorer.score(
            theCase,
            outcome: corrected(text, "Ich bin jetzt da und mude.", errors: [item("jetz", .spelling), item("mude", .spelling)]))
        #expect(score.categoryMatches == 1)
        #expect(score.unexplainedFixes == 0)
    }
}
