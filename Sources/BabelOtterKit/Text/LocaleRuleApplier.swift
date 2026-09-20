import Foundation

/// Applies a language's locale rules to everything except the protected spans.
///
/// `FR-GLO-03`: locale rules must never rewrite the interior of a restored
/// do-not-translate term. A product name spelled with an eszett keeps its eszett,
/// whatever Swiss orthography says about the prose around it.
///
/// Implemented as a single left-to-right walk that copies protected spans
/// through verbatim and rewrites only the gaps. `replacingOccurrences` over the
/// whole string cannot express "except here", and repairing damaged spans
/// afterwards is guesswork about where they used to be.
public enum LocaleRuleApplier {

    public static func apply(
        _ rules: [LocaleRule],
        to text: String,
        protecting ranges: [Range<String.Index>]
    ) -> String {
        guard !rules.isEmpty else { return text }

        // Callers assemble ranges in whatever order restoration produced them;
        // the walk below requires them ascending and non-overlapping.
        let ordered = ranges.sorted { $0.lowerBound < $1.lowerBound }

        var result = ""
        var cursor = text.startIndex
        for range in ordered {
            guard range.lowerBound >= cursor else { continue }
            result += rewrite(String(text[cursor..<range.lowerBound]), with: rules)
            result += text[range]
            cursor = range.upperBound
        }
        result += rewrite(String(text[cursor...]), with: rules)
        return result
    }

    /// Each rule applied to the whole fragment, in configured order, so the
    /// ordering of rules in a configuration file is meaningful.
    private static func rewrite(_ fragment: String, with rules: [LocaleRule]) -> String {
        rules.reduce(fragment) { text, rule in
            text.replacingOccurrences(of: rule.replace, with: rule.with)
        }
    }
}
