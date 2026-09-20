import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Post-processing runs in the order spec §8 mandates")
struct PostProcessorTests {

    private let processor = PostProcessor(rules: [LocaleRule(replace: "ß", with: "ss")])

    @Test("a DNT term containing ß survives; the prose around it does not")
    func protectedTermKeepsEszett() {
        let protected = TokenProtector.mask("Das Großmünster ist groß.", terms: ["Großmünster"])
        let finished = processor.finish(protected.text, protected: protected)
        #expect(finished.text == "Das Großmünster ist gross.")
        #expect(finished.problems.isEmpty)
    }

    @Test("with no protected terms, rules apply everywhere")
    func noTermsMeansPlainRules() {
        let protected = TokenProtector.mask("Die Straße ist groß.", terms: [])
        #expect(processor.finish(protected.text, protected: protected).text == "Die Strasse ist gross.")
    }

    @Test("a non-German target applies no rules")
    func noRulesForOtherLanguages() {
        let plain = PostProcessor(rules: [])
        let protected = TokenProtector.mask("The Straße stays.", terms: [])
        #expect(plain.finish(protected.text, protected: protected).text == "The Straße stays.")
    }

    @Test("a sentinel the model destroyed is reported, not silently pasted")
    func damageIsReported() {
        let protected = TokenProtector.mask("ZHAW rules", terms: ["ZHAW"])
        let finished = processor.finish("the model rewrote everything", protected: protected)
        #expect(finished.problems == [.sentinelMissing(index: 0, term: "ZHAW")])
    }

    @Test("the model's own ß in translated prose is still corrected")
    func modelOutputIsPostProcessed() {
        let protected = TokenProtector.mask("ZHAW", terms: ["ZHAW"])
        let finished = processor.finish("⟦DNT0⟧ ist eine große Schule", protected: protected)
        #expect(finished.text == "ZHAW ist eine grosse Schule")
    }

    @Test("several protected terms are each shielded from the rules")
    func multipleTermsShielded() {
        let protected = TokenProtector.mask("Größe and Straßen", terms: ["Größe", "Straßen"])
        let finished = processor.finish(protected.text, protected: protected)
        #expect(finished.text == "Größe and Straßen")
        #expect(finished.problems.isEmpty)
    }

    @Test("a convenience initialiser takes the rules from the target language")
    func builtFromLanguage() {
        let processor = PostProcessor(target: .swissGerman)
        let protected = TokenProtector.mask("groß", terms: [])
        #expect(processor.finish(protected.text, protected: protected).text == "gross"      )
    }

    /// The ordering invariant of spec §8, made observable.
    ///
    /// A `ß`→`ss` rule cannot distinguish the two orders: masking hides the
    /// term either way, so a DNT term keeps its `ß` under both. What *can*
    /// distinguish them is a rule whose pattern occurs inside the sentinel
    /// itself. Applying rules before restoring rewrites the mask, and the term
    /// is then unrecoverable — which is the general reason §8 fixes the order,
    /// not merely a quirk of this rule.
    @Test("a rule matching the sentinel proves rules run after restoration")
    func rulesRunAfterRestoration() {
        let processor = PostProcessor(rules: [LocaleRule(replace: "NT", with: "nt")])
        let protected = TokenProtector.mask("ZHAW matters", terms: ["ZHAW"])
        let finished = processor.finish(protected.text, protected: protected)
        #expect(finished.text == "ZHAW matters")
        #expect(finished.problems.isEmpty, "restoring after the rules would have lost the term")
    }

    @Test("English as a target carries no rules")
    func englishHasNoRules() {
        let processor = PostProcessor(target: .english)
        let protected = TokenProtector.mask("groß", terms: [])
        #expect(processor.finish(protected.text, protected: protected).text == "groß")
    }
}
