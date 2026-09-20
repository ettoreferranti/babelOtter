import Foundation

/// Damage to the sentinel scheme, found during restoration.
///
/// Reported rather than repaired. A model that mangles a sentinel has already
/// lost the term; guessing where it went would paste something plausible and
/// wrong into the user's email.
public enum ProtectionProblem: Sendable, Equatable {
    /// A sentinel that went into the prompt did not come back.
    case sentinelMissing(index: Int, term: String)
    /// A sentinel-shaped string that maps to no known term.
    case sentinelDebris(String)
}

/// Text with protected terms replaced by sentinels, plus the key to undo it.
public struct ProtectedText: Sendable, Equatable {
    public let text: String
    /// `terms[i]` is the term behind sentinel `i`, after filtering and
    /// longest-first ordering.
    public let terms: [String]
}

/// Restored text, the spans that must not be touched again, and any damage.
public struct RestoredText: Sendable, Equatable {
    public let text: String
    /// Ranges of the restored terms, in `text`'s own coordinates. These exist
    /// only after restoration, which is why spec section 8 fixes that order.
    public let protectedRanges: [Range<String.Index>]
    public let problems: [ProtectionProblem]
}

/// Masks do-not-translate terms to sentinels and restores them verbatim.
///
/// `FR-GLO-02`. The sentinel is [[DNT0]] with U+27E6/U+27E7 corner brackets,
/// because they are not reachable from a German or English keyboard, so they
/// cannot collide with the user's own writing, and because a model is far less
/// likely to "helpfully" translate them than it is a word in angle brackets.
public enum TokenProtector {

    // Written as escapes rather than literal glyphs because every source file
    // under BabelOtterKit is ASCII-only -- see AsciiSourceTests for why. The
    // characters are U+27E6 MATHEMATICAL LEFT WHITE SQUARE BRACKET and its
    // right-hand partner U+27E7, so a sentinel reads as an unmistakable
    // non-keyboard token both to a human and to a model.
    private static let opening = "\u{27E6}"
    private static let closing = "\u{27E7}"
    private static let prefix = "\u{27E6}DNT"

    static func sentinel(_ index: Int) -> String { "\(prefix)\(index)\(closing)" }

    /// Replaces each term with its sentinel, longest term first.
    public static func mask(_ text: String, terms: [String]) -> ProtectedText {
        let ordered = orderedTerms(terms)
        guard !ordered.isEmpty else { return ProtectedText(text: text, terms: ordered) }

        // Walked as a shrinking Substring rather than an index compared against
        // endIndex. `first` is nil exactly when the comparison would have
        // ended the loop, so nothing is lost -- and muter mis-parses a
        // relational operator in a while condition, more so with a label on it.
        // That kept making this file unmeasurable on CI while building clean
        // locally. Substring shares its parent's indices, so `matches` still
        // sees positions in `text`.
        var result = ""
        var remainder = Substring(text)
        while let character = remainder.first {
            let match = ordered.enumerated().first { _, term in
                matches(term, in: text, at: remainder.startIndex)
            }
            guard let match else {
                result.append(character)
                remainder = remainder.dropFirst()
                continue
            }
            result += sentinel(match.offset)
            remainder = remainder.dropFirst(match.element.count)
        }
        return ProtectedText(text: result, terms: ordered)
    }

    /// Puts the original terms back and says where they landed.
    public static func restore(_ text: String, from protected: ProtectedText) -> RestoredText {
        var result = ""
        var offsets: [(start: Int, end: Int)] = []
        var problems: [ProtectionProblem] = []
        var seen: Set<Int> = []

        // Same shrinking-Substring walk as `mask`, and for the same reason.
        var remainder = Substring(text)
        while let character = remainder.first {
            let index = remainder.startIndex
            guard let parsed = parseSentinel(in: text, at: index) else {
                result.append(character)
                remainder = remainder.dropFirst()
                continue
            }
            // `indices.contains` rather than a bounds comparison: it says what
            // the check is for, and it cannot be off by one.
            if protected.terms.indices.contains(parsed.index) {
                let start = result.count
                result += protected.terms[parsed.index]
                offsets.append((start: start, end: result.count))
                seen.insert(parsed.index)
            } else {
                let literal = String(text[index..<parsed.end])
                problems.append(.sentinelDebris(literal))
                result += literal
            }
            remainder = text[parsed.end...]
        }

        // Only terms that actually went into the prompt can come back, so a term
        // the source text never contained is not a missing sentinel.
        for (termIndex, term) in protected.terms.enumerated()
        where protected.text.contains(sentinel(termIndex)) && !seen.contains(termIndex) {
            problems.append(.sentinelMissing(index: termIndex, term: term))
        }

        return RestoredText(
            text: result,
            protectedRanges: offsets.map { ranges(in: result, from: $0.start, to: $0.end) },
            problems: problems
        )
    }

    // MARK: - Term ordering

    /// Non-empty, de-duplicated, longest first.
    ///
    /// Longest-first is what makes `"Otterbach School of Engineering"` mask as one
    /// unit instead of leaving `" School of Engineering"` exposed after
    /// `"Otterbach"` matched its prefix. Ties break on the configured order so the
    /// result is deterministic, which `sorted(by:)` alone does not guarantee.
    private static func orderedTerms(_ terms: [String]) -> [String] {
        var unique: [String] = []
        for term in terms
        where !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !unique.contains(term) {
            unique.append(term)
        }
        return unique.enumerated()
            .sorted { left, right in
                // if/else rather than a ternary, for the reason given in
                // PromptBuilder.languages.
                if left.element.count != right.element.count {
                    return left.element.count > right.element.count
                }
                return left.offset < right.offset
            }
            .map(\.element)
    }

    // MARK: - Matching

    /// True when `term` sits at `index` bounded by non-word characters.
    ///
    /// The boundary check is what stops `"IT"` turning the user's `"Item"` into
    /// a sentinel. `isLetter`/`isNumber` are Unicode-aware, so IT followed by an umlaut is one
    /// word; an ASCII-only test would treat the umlaut as a boundary and corrupt it.
    private static func matches(_ term: String, in text: String, at index: String.Index) -> Bool {
        guard text[index...].hasPrefix(term) else { return false }
        // `last` and `first` on the slices either side, rather than comparing
        // the index against startIndex and endIndex: nil means "no character
        // there", which is the same answer the comparison gave, and it leaves
        // muter nothing to mis-splice.
        if let before = text[..<index].last, isWordCharacter(before) { return false }
        let end = text.index(index, offsetBy: term.count)
        if let after = text[end...].first, isWordCharacter(after) { return false }
        return true
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    // MARK: - Sentinel parsing

    /// Parses a U+27E6 DNT <digits> U+27E7 sentinel at `index`, or returns `nil`.
    private static func parseSentinel(
        in text: String, at index: String.Index
    ) -> (index: Int, end: String.Index)? {
        guard text[index...].hasPrefix(prefix) else { return nil }
        let afterPrefix = text.index(index, offsetBy: prefix.count)

        // prefix/first rather than an index walk guarded by bounds comparisons.
        // Those comparisons carried no information -- `first` is nil at the end
        // of the string, which is the same answer -- and muter mis-parses a
        // relational operator sitting inside a multi-clause guard, which made
        // this whole file intermittently unmeasurable. It built clean locally
        // and failed on CI, which is the worst way to find out.
        let digits = text[afterPrefix...].prefix { $0.isNumber }
        guard let parsed = Int(digits) else { return nil }

        let afterDigits = text.index(afterPrefix, offsetBy: digits.count)
        guard text[afterDigits...].first == Character(closing) else { return nil }
        return (index: parsed, end: text.index(after: afterDigits))
    }

    private static func ranges(in text: String, from start: Int, to end: Int)
        -> Range<String.Index>
    {
        let lower = text.index(text.startIndex, offsetBy: start)
        let upper = text.index(text.startIndex, offsetBy: end)
        return lower..<upper
    }
}
