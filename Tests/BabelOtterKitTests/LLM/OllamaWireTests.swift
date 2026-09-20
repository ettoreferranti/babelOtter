import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Ollama wire contracts")
struct OllamaWireTests {

    // MARK: - Single lines

    @Test("a content delta decodes to its text")
    func deltaLine() {
        let line = #"{"message":{"role":"assistant","content":"Hal"},"done":false}"#
        #expect(OllamaWire.event(from: line) == .delta("Hal"))
    }

    @Test("the done chunk finishes the stream")
    func doneLine() {
        let line = #"{"message":{"role":"assistant","content":""},"done":true}"#
        #expect(OllamaWire.event(from: line) == .finished)
    }

    @Test("done wins over content, because Ollama sends empty content there")
    func doneWinsOverContent() {
        let line = #"{"message":{"role":"assistant","content":"x"},"done":true}"#
        #expect(OllamaWire.event(from: line) == .finished)
    }

    @Test("an empty delta is still a delta, not a malformed line")
    func emptyDelta() {
        let line = #"{"message":{"role":"assistant","content":""},"done":false}"#
        #expect(OllamaWire.event(from: line) == .delta(""))
    }

    @Test("valid JSON of the wrong shape is reported, not skipped")
    func wrongShape() {
        let line = #"{"unexpected":true}"#
        #expect(OllamaWire.event(from: line) == .malformed(line: line))
    }

    @Test("a line that is not JSON at all is reported")
    func notJSON() {
        let line = "Error: model not found"
        #expect(OllamaWire.event(from: line) == .malformed(line: line))
    }

    @Test("an unfinished chunk with no message is reported")
    func missingMessage() {
        let line = #"{"done":false}"#
        #expect(OllamaWire.event(from: line) == .malformed(line: line))
    }

    @Test("unknown fields are ignored rather than failing the line")
    func unknownFieldsTolerated() {
        let line = #"{"model":"m","created_at":"t","message":{"role":"assistant","content":"a"},"done":false,"eval_count":7}"#
        #expect(OllamaWire.event(from: line) == .delta("a"))
    }

    // MARK: - The recorded stream

    @Test("the recorded fixture replays to a complete response, then finishes")
    func replaysFixture() throws {
        let url = SourceTree.repositoryRoot
            .appending(path: "Tests/Fixtures/ollama/chat-stream.ndjson")
        let contents = try String(contentsOf: url, encoding: .utf8)

        var framer = NDJSONFramer()
        var events = contents.split(separator: "\n").flatMap { chunk in
            framer.consume(String(chunk) + "\n").map(OllamaWire.event(from:))
        }
        events += framer.finish().map(OllamaWire.event(from:))

        #expect(events.last == .finished)
        #expect(!events.contains { if case .malformed = $0 { true } else { false } })

        let text = events.reduce(into: "") { result, event in
            if case .delta(let piece) = event { result += piece }
        }
        #expect(text == #"{"detected_source": "en", "blocks": ["Guten Morgen"]}"#)
    }

    @Test("the fixture's text is a response the parser understands end to end")
    func fixtureFeedsTheParser() throws {
        let url = SourceTree.repositoryRoot
            .appending(path: "Tests/Fixtures/ollama/chat-stream.ndjson")
        let contents = try String(contentsOf: url, encoding: .utf8)
        var framer = NDJSONFramer()
        var text = ""
        for line in framer.consume(contents) + framer.finish() {
            if case .delta(let piece) = OllamaWire.event(from: line) { text += piece }
        }
        guard case .decoded(let response) = ResponseParser.parseTranslate(text) else {
            Issue.record("the fixture should parse as a translate response")
            return
        }
        #expect(response.blocks == ["Guten Morgen"])
        #expect(response.detectedSource == "en")
    }

    // MARK: - Request and catalogue shapes

    @Test("a chat request encodes the fields Ollama expects")
    func chatRequestEncodes() throws {
        let request = ChatRequest(
            model: "mistral-small3.2:24b",
            messages: [ChatMessage(role: "user", content: "hallo")],
            stream: true)
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(request)) as? [String: Any]
        #expect(json?["model"] as? String == "mistral-small3.2:24b")
        #expect(json?["stream"] as? Bool == true)
        #expect((json?["messages"] as? [[String: Any]])?.count == 1)
    }

    @Test("an installed-model catalogue decodes")
    func tagsDecode() throws {
        let json = #"{"models":[{"name":"mistral-small3.2:24b","size":15000000000}]}"#
        let decoded = try JSONDecoder.responseContract.decode(
            TagsResponse.self, from: Data(json.utf8))
        #expect(decoded.models.first?.name == "mistral-small3.2:24b")
    }

    @Test("pull progress decodes, with the byte counts optional")
    func pullProgressDecodes() throws {
        let withCounts = #"{"status":"downloading","completed":50,"total":100}"#
        let decoded = try JSONDecoder.responseContract.decode(
            PullProgress.self, from: Data(withCounts.utf8))
        #expect(decoded.completed == 50)

        let bare = #"{"status":"verifying sha256 digest"}"#
        let sparse = try JSONDecoder.responseContract.decode(
            PullProgress.self, from: Data(bare.utf8))
        #expect(sparse.total == nil)
    }

    @Test("pull progress reports a fraction only when both counts are present")
    func pullProgressFraction() {
        #expect(PullProgress(status: "d", completed: 50, total: 100).fraction == 0.5)
        #expect(PullProgress(status: "d", completed: 50, total: nil).fraction == nil)
        #expect(PullProgress(status: "d", completed: nil, total: 100).fraction == nil)
        #expect(PullProgress(status: "d", completed: 1, total: 0).fraction == nil)
    }
}
