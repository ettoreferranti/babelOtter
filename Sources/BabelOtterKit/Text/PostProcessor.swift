import Foundation

/// The post-processing chain, in the one order spec section 8 permits.
///
/// **Restore sentinels first, then apply locale rules to everything except the
/// restored spans.**
///
/// The order is load-bearing, and it is worth stating exactly why, because it is
/// easy to talk yourself out of. Applying rules to the *masked* text and
/// restoring afterwards would also leave a DNT term's eszett intact -- the two
/// orders agree on that case, so it is not the thing that distinguishes them.
/// What distinguishes them is that a rule pass over masked text cannot protect
/// anything at all: the spans do not exist yet. ``TokenProtector/restore(_:from:)``
/// is what produces the ranges, in the restored text's own coordinates, and
/// those ranges are the only thing standing between Swiss orthography and the
/// interior of a product name.
///
/// So the invariant the tests pin is not "restore is called first" but "the
/// ranges handed to the applier are the ones restoration produced".
public struct PostProcessor: Sendable {

    public let rules: [LocaleRule]

    public init(rules: [LocaleRule]) {
        self.rules = rules
    }

    /// Takes the rules from the target language, so adding a language by
    /// configuration gets post-processing with no code change (`FR-LNG-02`).
    public init(target: LanguageConfig) {
        self.init(rules: target.localeRules)
    }

    public func finish(
        _ modelOutput: String,
        protected: ProtectedText
    ) -> (text: String, problems: [ProtectionProblem]) {
        let restored = TokenProtector.restore(modelOutput, from: protected)
        let text = LocaleRuleApplier.apply(
            rules, to: restored.text, protecting: restored.protectedRanges)
        return (text: text, problems: restored.problems)
    }
}
