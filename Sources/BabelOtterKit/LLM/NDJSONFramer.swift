import Foundation

/// Splits a byte stream into newline-delimited JSON lines, across packet
/// boundaries.
///
/// Separated from the client on purpose. #41's requirement -- "a partial line
/// split across packets is buffered and parsed correctly once complete" -- is a
/// framing property, not a networking one, and deserves a test that needs no
/// daemon. Everything here runs in CI.
public struct NDJSONFramer: Sendable {

    private var buffer = ""

    public init() {}

    /// Complete lines from `chunk`, holding any trailing partial for later.
    ///
    /// Blank and whitespace-only lines are dropped rather than returned.
    /// Ollama's stream contains them, and passing them on would push the "is
    /// this malformed?" decision onto every caller, where it would be answered
    /// differently each time.
    public mutating func consume(_ chunk: String) -> [String] {
        buffer += chunk
        // `isNewline` rather than a literal "\n". Swift folds CRLF into a
        // single Character, so splitting on "\n" never matches a \r\n ending
        // and the whole stream buffers forever without ever emitting a line.
        guard buffer.contains(where: \.isNewline) else { return [] }

        var completed: [String] = []
        // omittingEmptySubsequences off, so the trailing element is the partial
        // line -- including the empty string when the chunk ends exactly on a
        // newline, which is what leaves the buffer clean.
        var pieces = buffer.split(
            omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let remainder = pieces.removeLast()

        for piece in pieces {
            let line = trimmed(piece)
            if !line.isEmpty { completed.append(line) }
        }
        buffer = String(remainder)
        return completed
    }

    /// Whatever is left, so a final line with no newline is not silently lost.
    ///
    /// That is the failure this method exists to prevent: the last token of a
    /// generation disappearing because the stream ended without a terminator.
    /// The buffer is cleared, so calling this twice does not repeat the line.
    public mutating func finish() -> [String] {
        let line = trimmed(Substring(buffer))
        buffer = ""
        return line.isEmpty ? [] : [line]
    }

    /// Trailing carriage returns come from CRLF, which `split` on `\n` leaves
    /// behind and `JSONDecoder` would then choke on.
    private func trimmed(_ piece: Substring) -> String {
        piece.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
