import Foundation

public enum DiffSegment: Sendable, Equatable {
    case same(String)
    case removed(String)
    case added(String)
}

/// A word-level diff (#40): the longest common subsequence of word,
/// whitespace and punctuation tokens.
///
/// Knows nothing about correction, so Re-pitch can use it too. Every result
/// satisfies two invariants the popup depends on: `same` plus `removed`
/// rebuilds the original exactly, and `same` plus `added` rebuilds the
/// revision exactly.
public enum WordDiff {

    /// Above this many token pairs, the quadratic table is not worth
    /// building. A selection that large is shown as one replacement rather
    /// than stalling the popup.
    static let maximumCells = 4_000_000

    /// Above this many tokens on either side, even a table within
    /// `maximumCells` (one huge side against a tiny one) is not worth
    /// building: the table's own allocation and the backtrack it drives
    /// both scale with the larger side, not with the product (#41).
    static let maximumTokens = 2_000

    public static func diff(_ original: String, _ revised: String) -> [DiffSegment] {
        let a = tokens(original)
        let b = tokens(revised)

        var prefix = 0
        while prefix < a.count && prefix < b.count && a[prefix] == b[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < a.count - prefix && suffix < b.count - prefix
            && a[a.count - 1 - suffix] == b[b.count - 1 - suffix]
        {
            suffix += 1
        }

        var builder = SegmentBuilder()
        for token in a[0..<prefix] { builder.add(.same, token) }
        let middleA = Array(a[prefix..<(a.count - suffix)])
        let middleB = Array(b[prefix..<(b.count - suffix)])
        middle(middleA, middleB, into: &builder)
        for token in a[(a.count - suffix)...] { builder.add(.same, token) }
        return builder.build()
    }

    /// The changed middle, by longest common subsequence. On a tie, the
    /// removal is shown before the addition.
    private static func middle(_ a: [String], _ b: [String], into builder: inout SegmentBuilder) {
        guard a.count * b.count <= maximumCells && max(a.count, b.count) <= maximumTokens else {
            builder.add(.removed, a.joined())
            builder.add(.added, b.joined())
            return
        }
        var lengths = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                if a[i] == b[j] {
                    lengths[i][j] = lengths[i + 1][j + 1] + 1
                } else {
                    lengths[i][j] = max(lengths[i + 1][j], lengths[i][j + 1])
                }
            }
        }
        var i = 0
        var j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] {
                builder.add(.same, a[i])
                i += 1
                j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                builder.add(.removed, a[i])
                i += 1
            } else {
                builder.add(.added, b[j])
                j += 1
            }
        }
        for token in a[i...] { builder.add(.removed, token) }
        for token in b[j...] { builder.add(.added, token) }
    }

    /// Accumulates consecutive same-kind tokens into one segment.
    ///
    /// Re-concatenating `x + y` for every token, where `x` is the text just
    /// unwrapped from the previous segment's enum case, is quadratic: the
    /// unwrap leaves the array's stored copy holding the same buffer, so the
    /// string is never uniquely referenced and every `+` pays for a fresh
    /// copy of everything accumulated so far (#41). Growing a single local
    /// `String` with `+=` instead stays uniquely referenced, so Swift can
    /// grow its buffer in place with amortised O(1) appends; the run is
    /// only boxed into a `DiffSegment` once, when it ends.
    private struct SegmentBuilder {
        enum Kind: Equatable { case same, removed, added }

        private var segments: [DiffSegment] = []
        private var kind: Kind?
        private var text = ""

        mutating func add(_ next: Kind, _ token: String) {
            guard !token.isEmpty else { return }
            if next == kind {
                text += token
            } else {
                flush()
                kind = next
                text = token
            }
        }

        private mutating func flush() {
            guard let kind else { return }
            switch kind {
            case .same: segments.append(.same(text))
            case .removed: segments.append(.removed(text))
            case .added: segments.append(.added(text))
            }
            text = ""
        }

        mutating func build() -> [DiffSegment] {
            flush()
            kind = nil
            return segments
        }
    }

    private enum TokenKind { case word, space, punctuation }

    private static func kind(of character: Character) -> TokenKind {
        if character.isLetter || character.isNumber { return .word }
        if character.isWhitespace { return .space }
        return .punctuation
    }

    /// Words and whitespace runs are single tokens; each punctuation
    /// character is its own token.
    static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var currentKind: TokenKind?
        for character in text {
            let next = kind(of: character)
            if next == .punctuation {
                if !current.isEmpty { result.append(current) }
                result.append(String(character))
                current = ""
                currentKind = nil
            } else if next == currentKind {
                current.append(character)
            } else {
                if !current.isEmpty { result.append(current) }
                current = String(character)
                currentKind = next
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
