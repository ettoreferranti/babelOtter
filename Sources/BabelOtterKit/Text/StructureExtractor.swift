import Foundation

public enum StructureError: Error, Equatable {
    /// The model returned a different number of blocks than it was given.
    /// Never repaired by padding or truncating -- see ``BlockCountPolicy``.
    case blockCountMismatch(expected: Int, received: Int)
}

/// One source line, decomposed so that its parts concatenate back to the
/// original exactly.
///
/// `indent + marker + prose + trailing + terminator` **is** the line. Nothing is
/// normalised, inferred or re-derived on the way back, which is what makes the
/// round trip byte-identical rather than merely close.
struct SkeletonLine: Sendable, Equatable {
    /// Leading whitespace. For a line with no prose, the entire line content.
    let indent: String
    /// A list marker including the whitespace that follows it, or empty.
    let marker: String
    /// The prose as it was, used when this line contributes no block.
    let prose: String
    /// Whitespace between the prose and the line ending.
    let trailing: String
    /// `"\r\n"`, `"\n"`, `"\r"`, or `""` on a final line with no newline.
    let terminator: String
    /// Index into the block array, or `nil` for a line the model never sees.
    let blockIndex: Int?
}

/// The structure of a text with its prose removed.
///
/// The model only ever sees ``ExtractedText/blocks``; everything that makes the
/// text *look* the way it does stays here, on this side of the network boundary.
public struct Skeleton: Sendable, Equatable {

    let lines: [SkeletonLine]

    /// How many blocks this skeleton expects back.
    ///
    /// Stored at extraction rather than recounted, so the index arithmetic
    /// exists in exactly one place and a test can pin it there.
    public let blockCount: Int
}

public struct ExtractedText: Sendable, Equatable {
    public let skeleton: Skeleton
    public let blocks: [String]
}

/// Splits text into a skeleton plus prose blocks, and puts it back together.
///
/// `FR-TRN-04`: line breaks, blank lines, list markers and indentation survive
/// the round trip. The spec names this file first among mutation targets,
/// because wrong block-index arithmetic does not crash -- it silently returns the
/// user's paragraphs in the wrong order.
public enum StructureExtractor {

    /// Bullet characters that begin a list item when followed by whitespace.
    private static let bulletMarkers: Set<Character> = ["-", "*", "+"]

    public static func extract(_ text: String) -> ExtractedText {
        var lines: [SkeletonLine] = []
        var blocks: [String] = []

        for raw in splitPreservingTerminators(text) {
            let parsed = parse(content: raw.content)
            var blockIndex: Int?
            if !parsed.prose.isEmpty {
                blockIndex = blocks.count
                blocks.append(parsed.prose)
            }
            lines.append(
                SkeletonLine(
                    indent: parsed.indent,
                    marker: parsed.marker,
                    prose: parsed.prose,
                    trailing: parsed.trailing,
                    terminator: raw.terminator,
                    blockIndex: blockIndex
                ))
        }

        return ExtractedText(
            skeleton: Skeleton(lines: lines, blockCount: blocks.count),
            blocks: blocks
        )
    }

    /// Re-applies blocks to a skeleton, or throws rather than guess.
    ///
    /// A count mismatch is never repaired here. Padding would invent empty
    /// paragraphs and truncating would drop the user's writing; both look like
    /// success. ``BlockCountPolicy`` decides what to do about it instead.
    public static func reapply(_ blocks: [String], to skeleton: Skeleton) throws -> String {
        guard blocks.count == skeleton.blockCount else {
            throw StructureError.blockCountMismatch(
                expected: skeleton.blockCount, received: blocks.count)
        }
        var result = ""
        for line in skeleton.lines {
            result += line.indent
            result += line.marker
            result += line.blockIndex.map { blocks[$0] } ?? line.prose
            result += line.trailing
            result += line.terminator
        }
        return result
    }

    // MARK: - Line splitting

    /// Splits into lines, recording each line's own terminator.
    ///
    /// Per-line rather than one detected style for the document, so mixed
    /// endings and a missing final newline both survive. Swift folds `\r\n` into
    /// a single `Character`, so the three cases are distinguished by comparing
    /// whole grapheme clusters rather than by peeking at the next scalar.
    private static func splitPreservingTerminators(
        _ text: String
    ) -> [(content: String, terminator: String)] {
        var lines: [(content: String, terminator: String)] = []
        var current = ""
        for character in text {
            // `isNewline` rather than three equality checks against "\r\n",
            // "\n" and "\r". Swift folds CRLF into one Character, so all three
            // are single graphemes and this covers them plus the rarer Unicode
            // line separators. The terminator is stored exactly as it appeared,
            // so widening what counts as a break cannot change the round trip.
            if character.isNewline {
                lines.append((current, String(character)))
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty {
            lines.append((current, ""))
        }
        return lines
    }

    // MARK: - Line parsing

    private static func parse(
        content: String
    ) -> (indent: String, marker: String, prose: String, trailing: String) {
        let indentEnd =
            content.firstIndex { !$0.isWhitespace } ?? content.endIndex
        let indent = String(content[content.startIndex..<indentEnd])
        let remainder = content[indentEnd...]

        // A line with nothing but whitespace is structure in its entirety.
        guard !remainder.isEmpty else {
            return (indent: content, marker: "", prose: "", trailing: "")
        }

        let markerLength = markerLength(in: remainder)
        let markerEnd = remainder.index(remainder.startIndex, offsetBy: markerLength)
        var marker = String(remainder[remainder.startIndex..<markerEnd])
        var body = remainder[markerEnd...]

        // Whitespace after a marker belongs to the marker, so prose starts at a
        // real character and comes back in the same column.
        if !marker.isEmpty {
            let bodyStart = body.firstIndex { !$0.isWhitespace } ?? body.endIndex
            marker += String(body[body.startIndex..<bodyStart])
            body = body[bodyStart...]
        }

        guard let lastProse = body.lastIndex(where: { !$0.isWhitespace }) else {
            return (indent: indent, marker: marker, prose: "", trailing: String(body))
        }
        let proseEnd = body.index(after: lastProse)
        return (
            indent: indent,
            marker: marker,
            prose: String(body[body.startIndex..<proseEnd]),
            trailing: String(body[proseEnd...])
        )
    }

    /// Length in characters of the list marker at the start of `remainder`, or 0.
    ///
    /// A marker is only a marker when whitespace follows it. Without that rule
    /// `-5 degrees` loses its minus sign and `1.5 metres` becomes a numbered
    /// list -- both silent corruptions of the user's own text.
    private static func markerLength(in remainder: Substring) -> Int {
        // Written with prefix/dropFirst rather than an index and a count.
        // Indexed access needed a bounds comparison at every step, and those
        // comparisons carried no information: with `remainder` non-empty,
        // `count > 1` and `count != 1` are the same test, so the bounds checks
        // were unkillable by any test and there was a subscript one edit away
        // from crashing. This version cannot read past the end at all.
        guard let first = remainder.first else { return 0 }
        let rest = remainder.dropFirst()

        if bulletMarkers.contains(first) {
            guard rest.first?.isWhitespace == true else { return 0 }
            return 1
        }

        if first.isNumber {
            let digits = remainder.prefix { $0.isNumber }
            let afterDigits = remainder.dropFirst(digits.count)
            guard let punctuation = afterDigits.first,
                punctuation == "." || punctuation == ")",
                afterDigits.dropFirst().first?.isWhitespace == true
            else { return 0 }
            return digits.count + 1
        }

        if first.isLetter {
            guard rest.first == ")", rest.dropFirst().first?.isWhitespace == true else {
                return 0
            }
            return 2
        }

        return 0
    }
}
