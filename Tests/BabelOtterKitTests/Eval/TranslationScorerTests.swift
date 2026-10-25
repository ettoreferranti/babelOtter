import Testing

@testable import BabelOtterKit

private func translationCase(
    _ text: String, _ direction: TranslationDirection = .englishToSwissGerman,
    terms: [String] = [], reference: String = "Referenz"
) -> TranslationCase {
    TranslationCase(
        id: "t", text: text, direction: direction, profileID: "colleagues", terms: terms,
        reference: reference)
}

@Suite("Eval: a translation scored against its case")
struct TranslationScorerTests {

    @Test("a German target must contain no eszett; an English one is not checked")
    func esszett() {
        let german = translationCase("Street.")
        #expect(TranslationScorer.score(german, outcome: .translated("Strasse.")).esszettAbsent == true)
        #expect(TranslationScorer.score(german, outcome: .translated("Stra\u{00DF}e.")).esszettAbsent == false)
        let english = translationCase("Strasse.", .swissGermanToEnglish)
        #expect(TranslationScorer.score(english, outcome: .translated("Street.")).esszettAbsent == nil)
        #expect(TranslationScorer.score(german, outcome: .failed(.emptyResponse)).esszettAbsent == false)
    }

    @Test("the check follows the target's rules: French has none, de-CH from French has its own (#81)")
    func localeRulesFollowTarget() throws {
        let french = translationCase("Street.", try #require(TranslationDirection(rawValue: "en-fr")))
        #expect(TranslationScorer.score(french, outcome: .translated("Stra\u{00DF}e.")).esszettAbsent == nil)
        let fromFrench = translationCase("Rue.", try #require(TranslationDirection(rawValue: "fr-de-ch")))
        #expect(TranslationScorer.score(fromFrench, outcome: .translated("Stra\u{00DF}e.")).esszettAbsent == false)
        #expect(TranslationScorer.score(fromFrench, outcome: .translated("Strasse.")).esszettAbsent == true)
    }

    @Test("a de-CH translation is checked for dialect words, as whole words (#123)")
    func dialect() throws {
        let german = translationCase("If it stays dry, we'll eat outside on Saturday.")
        let dialect = TranslationScorer.score(
            german, outcome: .translated("Wenns trocken bleibt, essen mer am Samschtig drausse."))
        #expect(dialect.dialectWords == ["mer", "drausse", "Samschtig"])
        let standard = TranslationScorer.score(
            german, outcome: .translated("Wenn es trocken bleibt, essen wir am Samstag draussen auf dem Meer."))
        #expect(standard.dialectWords == [])
        let capitalised = TranslationScorer.score(german, outcome: .translated("Isch guet. Uf wiederluege."))
        #expect(capitalised.dialectWords == ["isch", "uf"])
        let english = translationCase("Uf.", .swissGermanToEnglish)
        #expect(TranslationScorer.score(english, outcome: .translated("isch uf")).dialectWords == nil)
        let fromFrench = translationCase("Rue.", try #require(TranslationDirection(rawValue: "fr-de-ch")))
        #expect(TranslationScorer.score(fromFrench, outcome: .translated("Das isch gut.")).dialectWords == ["isch"])
    }

    @Test("every term must come back verbatim")
    func terms() {
        let theCase = translationCase("Meet Otterbach at Riverside.", terms: ["Otterbach", "Riverside"],
                                      reference: "Otterbach Riverside")
        let score = TranslationScorer.score(theCase, outcome: .translated("Treffen Sie Otterbach am Fluss."))
        #expect(score.missingTerms == ["Riverside"])
        #expect(!score.termsKept)
        let kept = TranslationScorer.score(theCase, outcome: .translated("Otterbach bei Riverside."))
        #expect(kept.termsKept)
    }

    @Test("a sentinel bracket left in the output fails the terms check")
    func sentinelDebris() {
        let theCase = translationCase("Hello.")
        let score = TranslationScorer.score(theCase, outcome: .translated("Hallo \u{27E6}DNT0\u{27E7}."))
        #expect(score.sentinelDebris)
        #expect(!score.termsKept)
        #expect(TranslationScorer.score(theCase, outcome: .translated("Hallo \u{27E7}")).sentinelDebris)
        #expect(!TranslationScorer.score(theCase, outcome: .translated("Hallo.")).sentinelDebris)
    }

    @Test("structure is the same block count and list markers", arguments: [
        ("- one\n- two", "- eins\n- zwei", true),
        ("- one\n- two", "eins und zwei", false),
        ("One.\n\nTwo.", "Eins.\n\nZwei.", true),
        ("One.\n\nTwo.", "Eins. Zwei.", false),
        ("1. one\n2. two", "- eins\n- zwei", false),
    ])
    func structure(source: String, output: String, kept: Bool) {
        #expect(TranslationScorer.sameStructure(source, output) == kept)
    }

    @Test("chrF is taken against the reference")
    func similarity() {
        let theCase = translationCase("Good morning.", reference: "Guten Morgen.")
        #expect(TranslationScorer.score(theCase, outcome: .translated("Guten Morgen.")).chrF > 99.9)
        #expect(TranslationScorer.score(theCase, outcome: .translated("xyz")).chrF == 0)
    }

    @Test("a failed translation fails every check")
    func failed() {
        let theCase = translationCase("Hi Otterbach.", terms: ["Otterbach"], reference: "Hallo Otterbach.")
        let score = TranslationScorer.score(theCase, outcome: .failed(.timeout))
        #expect(score.failure == .timeout)
        #expect(score.esszettAbsent == false)
        #expect(score.missingTerms == ["Otterbach"])
        #expect(!score.structureKept)
        #expect(score.chrF == 0)
        let english = translationCase("Hallo.", .swissGermanToEnglish, reference: "Hello.")
        #expect(TranslationScorer.score(english, outcome: .failed(.other)).esszettAbsent == nil)
    }

    @Test("a failed translation never counts as keeping its terms, even with none to keep")
    func failedWithoutTerms() {
        let theCase = translationCase("Hello.", reference: "Hallo.")
        #expect(!TranslationScorer.score(theCase, outcome: .failed(.timeout)).termsKept)
    }
}
