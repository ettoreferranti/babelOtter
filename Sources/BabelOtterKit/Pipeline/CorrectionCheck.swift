import Foundation

public struct CorrectionVerdict: Sendable, Equatable {
    public let warnings: [String]
    /// `FR-COR-06`: the text is unchanged and no error is listed. Suggestions
    /// alone do not make a text wrong.
    public let hasNoErrors: Bool
}

/// Checks a correction against itself; never repairs it.
///
/// The model is asked to apply errors only and list suggestions unapplied.
/// This is where that request is verified. Anything inconsistent becomes a
/// warning the user sees, because a correction that silently "fixed" its own
/// inconsistencies would be the model's guess presented as fact.
///
/// The "text changed but nothing is listed" rule below compares `original`
/// and `corrected` exactly as given, with no locale-rule normalisation: it
/// relies on the caller having already turned any locale-rule rewrite of the
/// user's own text into a listed error (`Corrector` does this for the
/// eszett), so that a rule-only change is never reported as "unexplained".
///
/// Known limitation: every presence check here is text-wide, not positional
/// -- a fragment that also happens to occur elsewhere in the text can
/// satisfy a check that was really about a different occurrence. The diff
/// remains the ground truth of what is actually pasted.
public enum CorrectionCheck {

    public static func check(
        original: String, corrected: String, items: [CorrectionError], rules: [LocaleRule]
    ) -> CorrectionVerdict {
        var warnings: [String] = []
        var errorCount = 0
        for item in items {
            if item.severity == .error {
                errorCount += 1
                // Compared both as written -- the raw user text, since it is
                // what the user actually typed -- and after the locale
                // rules, so a model that quotes a fragment in the target
                // spelling rather than the user's own (an eszett normalised
                // to "ss", say) is not accused of misquoting a fragment that
                // is really just the same word in the other spelling.
                if !item.original.isEmpty && !original.contains(item.original)
                    && !normalised(original, rules).contains(normalised(item.original, rules))
                {
                    warnings.append(
                        "A listed error is not in your text: \"\(item.original)\".")
                }
                let fragment = normalised(item.corrected, rules)
                if !fragment.isEmpty && !corrected.contains(fragment) {
                    warnings.append(
                        "A listed correction is missing from the corrected text: \"\(item.corrected)\".")
                }
            } else {
                let fragment = normalised(item.original, rules)
                let proposed = normalised(item.corrected, rules)
                if !fragment.isEmpty && !corrected.contains(fragment) && corrected.contains(proposed) {
                    warnings.append(
                        "A suggestion was applied although it should not have been: \"\(item.original)\".")
                }
            }
        }
        let changed = original != corrected
        if changed && errorCount == 0 {
            warnings.append("The text was changed, but no errors are listed.")
        }
        return CorrectionVerdict(warnings: warnings, hasNoErrors: !changed && errorCount == 0)
    }

    private static func normalised(_ fragment: String, _ rules: [LocaleRule]) -> String {
        LocaleRuleApplier.apply(rules, to: fragment, protecting: [])
    }
}
