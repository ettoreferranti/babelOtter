import Testing

@testable import BabelOtterKit

private func item(_ original: String, _ corrected: String, _ severity: Severity) -> CorrectionError {
    CorrectionError(
        original: original, corrected: corrected, category: .gender,
        explanationEn: "because", severity: severity)
}

private let swiss = LanguageConfig.swissGerman.localeRules

@Suite("A correction checked against itself")
struct CorrectionCheckTests {

    @Test("a consistent correction has no warnings")
    func consistent() {
        let verdict = CorrectionCheck.check(
            original: "mit der Kollege", corrected: "mit dem Kollegen",
            items: [item("der Kollege", "dem Kollegen", .error)], rules: swiss)
        #expect(verdict.warnings.isEmpty)
        #expect(!verdict.hasNoErrors)
    }

    @Test("an error whose correction is missing from the text is reported")
    func missingCorrection() {
        let verdict = CorrectionCheck.check(
            original: "mit der Kollege", corrected: "mit dem Kollegen",
            items: [item("der", "den", .error)], rules: swiss)
        #expect(verdict.warnings.contains { $0.contains("den") })
    }

    @Test("a suggestion that was applied anyway is reported")
    func appliedSuggestion() {
        let verdict = CorrectionCheck.check(
            original: "Das ist gut.", corrected: "Das ist hervorragend.",
            items: [item("gut", "hervorragend", .suggestion)], rules: swiss)
        #expect(verdict.warnings.contains { $0.contains("gut") })
    }

    @Test("a changed text with nothing listed is reported")
    func unexplainedChange() {
        let verdict = CorrectionCheck.check(
            original: "a", corrected: "b", items: [], rules: swiss)
        #expect(!verdict.warnings.isEmpty)
        #expect(!verdict.hasNoErrors)
    }

    @Test("an unchanged text with no errors is the no-errors result")
    func noErrors() {
        let verdict = CorrectionCheck.check(
            original: "Alles gut.", corrected: "Alles gut.", items: [], rules: swiss)
        #expect(verdict.hasNoErrors)
        #expect(verdict.warnings.isEmpty)
    }

    @Test("suggestions alone do not make a text wrong")
    func suggestionsOnly() {
        let verdict = CorrectionCheck.check(
            original: "Das ist gut.", corrected: "Das ist gut.",
            items: [item("gut", "hervorragend", .suggestion)], rules: swiss)
        #expect(verdict.hasNoErrors)
        #expect(verdict.warnings.isEmpty)
    }

    @Test("fragments are compared after the locale rules, as the text was")
    func normalised() {
        let verdict = CorrectionCheck.check(
            original: "die Strase", corrected: "die Strasse",
            items: [item("Strase", "Stra\u{00DF}e", .error)], rules: swiss)
        #expect(verdict.warnings.isEmpty)
    }

    @Test("an empty fragment is not checked for presence")
    func emptyFragment() {
        let verdict = CorrectionCheck.check(
            original: "sehr sehr gut", corrected: "sehr gut",
            items: [item("sehr ", "", .error)], rules: swiss)
        #expect(verdict.warnings.isEmpty)
    }

    @Test("an error listed on an unchanged text is not the no-errors result")
    func errorListedButUnchanged() {
        let verdict = CorrectionCheck.check(
            original: "mit dem Kollegen", corrected: "mit dem Kollegen",
            items: [item("der", "dem", .error)], rules: swiss)
        #expect(!verdict.hasNoErrors)
    }
}
