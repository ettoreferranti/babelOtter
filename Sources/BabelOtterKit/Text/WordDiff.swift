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

        var segments: [DiffSegment] = []
        append(.same(a[0..<prefix].joined()), to: &segments)
        let middleA = Array(a[prefix..<(a.count - suffix)])
        let middleB = Array(b[prefix..<(b.count - suffix)])
        for segment in middle(middleA, middleB) {
            append(segment, to: &segments)
        }
        append(.same(a[(a.count - suffix)...].joined()), to: &segments)
        return segments
    }

    /// The changed middle, by longest common subsequence. On a tie, the
    /// removal is shown before the addition.
    private static func middle(_ a: [String], _ b: [String]) -> [DiffSegment] {
        guard a.count * b.count <= maximumCells else {
            return [.removed(a.joined()), .added(b.joined())]
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
        var result: [DiffSegment] = []
        var i = 0
        var j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] {
                result.append(.same(a[i]))
                i += 1
                j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                result.append(.removed(a[i]))
                i += 1
            } else {
                result.append(.added(b[j]))
                j += 1
            }
        }
        for token in a[i...] { result.append(.removed(token)) }
        for token in b[j...] { result.append(.added(token)) }
        return result
    }

    /// Merges into the previous segment when both are the same kind; drops
    /// empty text.
    private static func append(_ segment: DiffSegment, to segments: inout [DiffSegment]) {
        guard !text(of: segment).isEmpty else { return }
        guard let last = segments.last else {
            segments.append(segment)
            return
        }
        switch (last, segment) {
        case (.same(let x), .same(let y)): segments[segments.count - 1] = .same(x + y)
        case (.removed(let x), .removed(let y)): segments[segments.count - 1] = .removed(x + y)
        case (.added(let x), .added(let y)): segments[segments.count - 1] = .added(x + y)
        default: segments.append(segment)
        }
    }

    private static func text(of segment: DiffSegment) -> String {
        switch segment {
        case .same(let text), .removed(let text), .added(let text): return text
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
