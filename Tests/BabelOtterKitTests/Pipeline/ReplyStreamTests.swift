import Foundation
import Testing

@testable import BabelOtterKit

private final class Scripted: ChatStreaming, @unchecked Sendable {
    let pieces: [String]
    private(set) var prompts: [String] = []
    private(set) var models: [String] = []
    init(_ pieces: [String]) { self.pieces = pieces }
    func chat(model: String, messages: [ChatMessage]) -> LazyStream<StreamEvent> {
        LazyStream { [self] in
            models.append(model)
            prompts.append(messages.last?.content ?? "")
            let pieces = self.pieces
            return AsyncThrowingStream { continuation in
                for piece in pieces { continuation.yield(.delta(piece)) }
                continuation.yield(.malformed(line: "noise"))
                continuation.yield(.finished)
                continuation.finish()
            }
        }
    }
}

/// `.timeLimit`: a stream that never finishes must fail, not hang (see the
/// muter trap in docs/HANDOFF.md).
@Suite("One streamed reply, collected", .timeLimit(.minutes(1)))
struct ReplyStreamTests {

    @Test("deltas are concatenated; malformed lines are skipped")
    func collects() async throws {
        let chat = Scripted(["{\"blocks\": [\"a", "b\"]}"])
        let raw = try await ReplyStream.collect(
            chat: chat, model: "m", prompt: "p", key: "blocks", onPartial: { _ in })
        #expect(raw == "{\"blocks\": [\"ab\"]}")
        #expect(chat.prompts == ["p"])
        #expect(chat.models == ["m"])
    }

    @Test("partials are reported once per change, never empty")
    func partials() async throws {
        let chat = Scripted(["{\"blocks\": [", "\"a", "\"", "]}"])
        var seen: [[String]] = []
        _ = try await ReplyStream.collect(
            chat: chat, model: "m", prompt: "p", key: "blocks", onPartial: { seen.append($0) })
        #expect(seen == [["a"]])
    }

    @Test("an empty reply comes back empty; the caller decides what that means")
    func empty() async throws {
        let raw = try await ReplyStream.collect(
            chat: Scripted([]), model: "m", prompt: "p", key: "blocks", onPartial: { _ in })
        #expect(raw.isEmpty)
    }
}
