import Foundation
import Testing

@testable import BabelOtterKit

@Suite("NDJSON framing survives packet boundaries")
struct NDJSONFramerTests {

    @Test("a whole line in one chunk is returned")
    func wholeLine() {
        var framer = NDJSONFramer()
        #expect(framer.consume("{\"a\":1}\n") == ["{\"a\":1}"])
    }

    @Test("a line split across two chunks is buffered until complete")
    func splitLine() {
        var framer = NDJSONFramer()
        #expect(framer.consume("{\"a\":") == [])
        #expect(framer.consume("1}\n") == ["{\"a\":1}"])
    }

    @Test("a line split across three chunks still arrives exactly once")
    func splitAcrossThree() {
        var framer = NDJSONFramer()
        #expect(framer.consume("{\"a") == [])
        #expect(framer.consume("\":") == [])
        #expect(framer.consume("1}\n") == ["{\"a\":1}"])
    }

    @Test("several lines in one chunk all come back, in order")
    func severalLines() {
        var framer = NDJSONFramer()
        #expect(framer.consume("{\"a\":1}\n{\"b\":2}\n") == ["{\"a\":1}", "{\"b\":2}"])
    }

    @Test("a trailing partial is kept, not emitted")
    func trailingPartialHeld() {
        var framer = NDJSONFramer()
        #expect(framer.consume("{\"a\":1}\n{\"b\"") == ["{\"a\":1}"])
    }

    @Test("finish returns the last line when the stream ends without a newline")
    func finishFlushes() {
        var framer = NDJSONFramer()
        _ = framer.consume("{\"a\":1}")
        #expect(framer.finish() == ["{\"a\":1}"])
    }

    @Test("finish on an empty buffer returns nothing")
    func finishEmpty() {
        var framer = NDJSONFramer()
        #expect(framer.finish() == [])
    }

    @Test("finish twice does not repeat the last line")
    func finishIsNotRepeatable() {
        var framer = NDJSONFramer()
        _ = framer.consume("{\"a\":1}")
        #expect(framer.finish() == ["{\"a\":1}"])
        #expect(framer.finish() == [])
    }

    @Test("blank lines are skipped rather than surfaced as malformed")
    func blankLinesSkipped() {
        var framer = NDJSONFramer()
        #expect(framer.consume("{\"a\":1}\n\n{\"b\":2}\n") == ["{\"a\":1}", "{\"b\":2}"])
    }

    @Test("a whitespace-only line is skipped too")
    func whitespaceOnlyLineSkipped() {
        var framer = NDJSONFramer()
        #expect(framer.consume("{\"a\":1}\n   \n{\"b\":2}\n") == ["{\"a\":1}", "{\"b\":2}"])
    }

    @Test("CRLF line endings frame correctly and leave no carriage return behind")
    func crlf() {
        var framer = NDJSONFramer()
        #expect(framer.consume("{\"a\":1}\r\n") == ["{\"a\":1}"])
    }

    @Test("an empty chunk yields nothing and disturbs nothing")
    func emptyChunk() {
        var framer = NDJSONFramer()
        #expect(framer.consume("{\"a\":") == [])
        #expect(framer.consume("") == [])
        #expect(framer.consume("1}\n") == ["{\"a\":1}"])
    }

    @Test("a chunk that is only a newline flushes the buffered line")
    func newlineOnlyChunk() {
        var framer = NDJSONFramer()
        #expect(framer.consume("{\"a\":1}") == [])
        #expect(framer.consume("\n") == ["{\"a\":1}"])
    }

    @Test("a realistic Ollama stream frames into its deltas")
    func realisticStream() {
        var framer = NDJSONFramer()
        var lines = framer.consume("{\"message\":{\"content\":\"Hal\"},\"done\":false}\n{\"mess")
        lines += framer.consume("age\":{\"content\":\"lo\"},\"done\":false}\n")
        lines += framer.consume("{\"done\":true}\n")
        #expect(lines.count == 3)
        #expect(lines[2] == "{\"done\":true}")
    }
}
