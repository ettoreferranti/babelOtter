import Foundation

/// The one place a prompt is streamed and collected.
///
/// `Translator` and `Corrector` both send one prompt, accumulate the deltas,
/// and preview a named block array as it grows. Having that loop in one place
/// means cancellation and preview behave identically for every action.
enum ReplyStream {

    static func collect(
        chat: any ChatStreaming, model: String, prompt: String, key: String,
        onPartial: ([String]) -> Void
    ) async throws -> String {
        var raw = ""
        var shown: [String] = []
        for try await event in chat.chat(
            model: model, messages: [ChatMessage(role: "user", content: prompt)])
        {
            try Task.checkCancellation()
            guard case .delta(let piece) = event else { continue }
            raw += piece
            let partial = PartialBlocks.extract(from: raw, key: key)
            guard !partial.isEmpty, partial != shown else { continue }
            shown = partial
            onPartial(partial)
        }
        return raw
    }
}
