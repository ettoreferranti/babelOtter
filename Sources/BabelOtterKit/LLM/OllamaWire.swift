import Foundation

/// One turn in a chat request or response.
public struct ChatMessage: Sendable, Codable, Equatable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// A `POST /api/chat` body.
public struct ChatRequest: Sendable, Codable, Equatable {
    public let model: String
    public let messages: [ChatMessage]
    public let stream: Bool

    public init(model: String, messages: [ChatMessage], stream: Bool = true) {
        self.model = model
        self.messages = messages
        self.stream = stream
    }
}

/// One NDJSON line of a streaming chat response.
///
/// Only the two fields that matter are decoded. Ollama also sends `model`,
/// `created_at`, `total_duration` and more, and a decoder that required them
/// would break the day one is renamed.
public struct ChatChunk: Sendable, Codable, Equatable {
    public let message: ChatMessage?
    public let done: Bool
}

public struct InstalledModel: Sendable, Codable, Equatable {
    public let name: String
    public let size: Int64?
}

/// `GET /api/tags` -- what is installed locally.
public struct TagsResponse: Sendable, Codable, Equatable {
    public let models: [InstalledModel]
}

/// One progress line from `POST /api/pull`.
public struct PullProgress: Sendable, Codable, Equatable {
    public let status: String
    public let completed: Int?
    public let total: Int?

    public init(status: String, completed: Int?, total: Int?) {
        self.status = status
        self.completed = completed
        self.total = total
    }

    /// Progress from 0 to 1, or `nil` when it cannot honestly be computed.
    ///
    /// Ollama emits status lines with no byte counts at all -- "verifying
    /// sha256 digest", "writing manifest" -- and a progress bar that invents a
    /// number for those is lying to the user about what it knows. `FR-OLL-03`
    /// wants progress shown; it does not want progress fabricated.
    public var fraction: Double? {
        guard let completed, let total, total > 0 else { return nil }
        return Double(completed) / Double(total)
    }
}

/// What one line of a stream means.
public enum StreamEvent: Sendable, Equatable {
    case delta(String)
    case finished
    /// #41: a malformed line is *reported*, never silently skipped. Throwing
    /// would abandon a whole generation over one bad line; skipping would hide
    /// a model that is misbehaving. So it is an event, and the caller decides.
    case malformed(line: String)
}

public enum OllamaWire {

    /// Classifies one NDJSON line.
    ///
    /// `done` is checked before content because Ollama's terminating chunk
    /// carries an empty `content` alongside `done: true` -- reproduced in
    /// `Tests/Fixtures/ollama/chat-stream.ndjson`. Were that ever to change and
    /// the final chunk carry text, this would drop it; the alternative ordering
    /// would be worse, because a stream that never reports finishing hangs.
    public static func event(from line: String) -> StreamEvent {
        guard
            let chunk = try? JSONDecoder.responseContract.decode(
                ChatChunk.self, from: Data(line.utf8))
        else {
            return .malformed(line: line)
        }
        if chunk.done { return .finished }
        guard let message = chunk.message else { return .malformed(line: line) }
        return .delta(message.content)
    }
}
