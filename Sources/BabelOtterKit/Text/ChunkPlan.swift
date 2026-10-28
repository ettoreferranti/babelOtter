import Foundation

/// A long text cut into chunks for the scratchpad (#84), one request each.
///
/// Cut only at blank lines, so a paragraph is never split: everything the
/// popup already does with lines, lists and indents still happens inside a
/// chunk. Paragraphs are packed in order up to `limit` characters; one longer
/// than that is a chunk of its own. What lies between two chunks -- the line
/// break and the blank lines -- is kept here verbatim, never sent, and put
/// back by `join`, so the result has the source's paragraphs.
public struct ChunkPlan: Sendable, Equatable {

    /// The spec's figure: well inside what one popup request already
    /// handles on the default model.
    public static let defaultLimit = 1_500

    /// Blank lines before the first paragraph.
    public let leading: String
    public let chunks: [String]
    /// `separators[i]` lies between `chunks[i]` and `chunks[i + 1]`.
    public let separators: [String]
    /// The last paragraph's line break and any blank lines after it.
    public let trailing: String

    public init(_ text: String, limit: Int = ChunkPlan.defaultLimit) {
        let parts = Self.paragraphs(of: text)
        var chunks: [String] = []
        var separators: [String] = []
        var current = ""
        var hasCurrent = false
        for index in parts.paragraphs.indices {
            let paragraph = parts.paragraphs[index]
            if !hasCurrent {
                current = paragraph
                hasCurrent = true
                continue
            }
            let gap = parts.gaps[index - 1]
            if Self.fits(current, gap, paragraph, limit) {
                current += gap + paragraph
            } else {
                chunks.append(current)
                separators.append(gap)
                current = paragraph
            }
        }
        if hasCurrent { chunks.append(current) }
        self.leading = parts.leading
        self.chunks = chunks
        self.separators = separators
        self.trailing = parts.trailing
    }

    /// The whole text as one chunk: Explain, which is never cut (#84).
    public static func whole(_ text: String) -> ChunkPlan {
        ChunkPlan(leading: "", chunks: [text], separators: [], trailing: "")
    }

    private init(leading: String, chunks: [String], separators: [String], trailing: String) {
        self.leading = leading
        self.chunks = chunks
        self.separators = separators
        self.trailing = trailing
    }

    /// The results put back between the kept separators. Fewer results than
    /// chunks is a partial result: those chunks, without the trailing part.
    public func join(_ results: [String]) -> String {
        var joined = leading
        if let first = results.first { joined += first }
        for index in results.indices.dropFirst() {
            joined += separators[index - 1] + results[index]
        }
        if results.count == chunks.count { joined += trailing }
        return joined
    }

    private static func fits(_ current: String, _ gap: String, _ next: String, _ limit: Int) -> Bool {
        current.count + gap.count + next.count <= limit
    }

    // MARK: - Paragraphs

    private struct Line {
        var content = ""
        var terminator = ""
        var isBlank: Bool { content.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private struct Parts {
        var leading = ""
        var paragraphs: [String] = []
        /// `gaps[i]` lies between `paragraphs[i]` and `paragraphs[i + 1]`.
        var gaps: [String] = []
        var trailing = ""
    }

    /// Lines end at any newline character; Swift reads CRLF as one.
    private static func lines(of text: String) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for character in text {
            if character.isNewline {
                line.terminator = String(character)
                lines.append(line)
                line = Line()
            } else {
                line.content.append(character)
            }
        }
        if !line.content.isEmpty { lines.append(line) }
        return lines
    }

    /// A paragraph is a run of lines with text. Its last line's break, and
    /// the blank lines after it, are the gap to the next paragraph.
    private static func paragraphs(of text: String) -> Parts {
        var parts = Parts()
        var paragraph = ""
        var gap = ""
        var inParagraph = false
        // Whether a blank line came since the paragraph's last line.
        var blankSince = false
        for line in lines(of: text) {
            if line.isBlank {
                if inParagraph {
                    gap += line.content + line.terminator
                    blankSince = true
                } else {
                    parts.leading += line.content + line.terminator
                }
                continue
            }
            if !inParagraph {
                inParagraph = true
                paragraph = line.content
                gap = line.terminator
                continue
            }
            if blankSince {
                parts.paragraphs.append(paragraph)
                parts.gaps.append(gap)
                paragraph = line.content
            } else {
                paragraph += gap + line.content
            }
            gap = line.terminator
            blankSince = false
        }
        if inParagraph {
            parts.paragraphs.append(paragraph)
            parts.trailing = gap
        }
        return parts
    }
}
