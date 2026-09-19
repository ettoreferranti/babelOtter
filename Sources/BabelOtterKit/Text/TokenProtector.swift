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
    /// only after restoration, which is why spec §8 fixes that order.
    public let protectedRanges: [Range<String.Index>]
    public let problems: [ProtectionProblem]
}

/// Masks do-not-translate terms to sentinels and restores them verbatim.
///
/// `FR-GLO-02`. The sentinel is `⟦DNT0⟧` — corner brackets (U+27E6/U+27E7)
/// because they are not reachable from a German or English keyboard, so they
/// cannot collide with the user's own writing, and because a model is far less
/// likely to "helpfully" translate them than it is a word in angle brackets.
public enum TokenProtector {

    private static let opening = "⟦"
    private static let closing = "⟧"
    private static let prefix = "⟦DNT"

    static func sentinel(_ index: Int) -> String { "\(prefix)\(index)\(closing)" }

    /// Replaces each term with its sentinel, longest term first.
    public static func mask(_ text: String, terms: [String]) -> ProtectedText {
        let ordered = orderedTerms(terms)
        guard !ordered.isEmpty else { return ProtectedText(text: text, terms: ordered) }

        var result = ""
        var index = text.startIndex
        scan: while index < text.endIndex {
            for (termIndex, term) in ordered.enumerated()
            where matches(term, in: text, at: index) {
                result += sentinel(termIndex)
                index = text.index(index, offsetBy: term.count)
                continue scan
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return ProtectedText(text: result, terms: ordered)
    }

    /// Puts the original terms back and says where they landed.
    public static func restore(_ text: String, from protected: ProtectedText) -> RestoredText {
        var result = ""
        var offsets: [(start: Int, end: Int)] = []
        var problems: [ProtectionProblem] = []
        var seen: Set<Int> = []

        var index = text.startIndex
        while index < text.endIndex {
            guard let parsed = parseSentinel(in: text, at: index) else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }
            if parsed.index < protected.terms.count {
                let start = result.count
                result += protected.terms[parsed.index]
                offsets.append((start: start, end: result.count))
                seen.insert(parsed.index)
            } else {
                let literal = String(text[index..<parsed.end])
                problems.append(.sentinelDebris(literal))
                result += literal
            }
            index = parsed.end
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
    /// Longest-first is what makes `"ZHAW School of Engineering"` mask as one
    /// unit instead of leaving `" School of Engineering"` exposed after
    /// `"ZHAW"` matched its prefix. Ties break on the configured order so the
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
                left.element.count != right.element.count
                    ? left.element.count > right.element.count
                    : left.offset < right.offset
            }
            .map(\.element)
    }

    // MARK: - Matching

    /// True when `term` sits at `index` bounded by non-word characters.
    ///
    /// The boundary check is what stops `"IT"` turning the user's `"Item"` into
    /// a sentinel. `isLetter`/`isNumber` are Unicode-aware, so `"ITär"` is one
    /// word — an ASCII-only test would treat `ä` as a boundary and corrupt it.
    private static func matches(_ term: String, in text: String, at index: String.Index) -> Bool {
        guard text[index...].hasPrefix(term) else { return false }
        if index > text.startIndex, isWordCharacter(text[text.index(before: index)]) {
            return false
        }
        let end = text.index(index, offsetBy: term.count)
        if end < text.endIndex, isWordCharacter(text[end]) { return false }
        return true
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    // MARK: - Sentinel parsing

    /// Parses `⟦DNT<digits>⟧` at `index`, or returns `nil`.
    private static func parseSentinel(
        in text: String, at index: String.Index
    ) -> (index: Int, end: String.Index)? {
        guard text[index...].hasPrefix(prefix) else { return nil }
        var cursor = text.index(index, offsetBy: prefix.count)
        var digits = ""
        while cursor < text.endIndex, text[cursor].isNumber {
            digits.append(text[cursor])
            cursor = text.index(after: cursor)
        }
        guard !digits.isEmpty, cursor < text.endIndex, text[cursor] == Character(closing),
            let parsed = Int(digits)
        else { return nil }
        return (index: parsed, end: text.index(after: cursor))
    }

    private static func ranges(in text: String, from start: Int, to end: Int)
        -> Range<String.Index>
    {
        let lower = text.index(text.startIndex, offsetBy: start)
        let upper = text.index(text.startIndex, offsetBy: end)
        return lower..<upper
    }
}
