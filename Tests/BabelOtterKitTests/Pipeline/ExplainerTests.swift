import Foundation
import Testing

@testable import BabelOtterKit

private final class ScriptedChat: ChatStreaming, @unchecked Sendable {
    private var replies: [[String]]
    private(set) var prompts: [String] = []
    private(set) var models: [String] = []
    init(_ replies: [[String]]) { self.replies = replies }
    func chat(model: String, messages: [ChatMessage]) -> LazyStream<StreamEvent> {
        LazyStream { [self] in
            models.append(model)
            prompts.append(messages.last?.content ?? "")
            let reply = replies.isEmpty ? [] : replies.removeFirst()
            return AsyncThrowingStream { continuation in
                for piece in reply { continuation.yield(.delta(piece)) }
                continuation.yield(.finished)
                continuation.finish()
            }
        }
    }
}

private struct FixedRecognizer: LanguageRecognizing {
    let code: String?
    func hypotheses(for text: String) -> [LanguageCode: Double] {
        guard let code else { return [:] }
        return [LanguageCode(code): 0.99]
    }
}

private func collect(_ stream: LazyStream<ExplanationEvent>) async throws -> [ExplanationEvent] {
    var events: [ExplanationEvent] = []
    for try await event in stream { events.append(event) }
    return events
}

private func result(_ events: [ExplanationEvent]) -> ExplanationResult? {
    guard case .finished(let result) = events.last else { return nil }
    return result
}

private func summaries(_ events: [ExplanationEvent]) -> [String] {
    var found: [String] = []
    for event in events {
        if case .summary(let text) = event { found.append(text) }
    }
    return found
}

private func note(_ phrase: String, _ explanation: String) -> String {
    "{\"phrase\": \"\(phrase)\", \"explanation_en\": \"\(explanation)\"}"
}

private func reply(_ summary: String, _ notes: [String] = []) -> [String] {
    ["{\"summary_en\": \"\(summary)\", \"notes\": [\(notes.joined(separator: ", "))]}"]
}

@Suite("The explainer, from German text to an English explanation", .timeLimit(.minutes(1)))
struct ExplainerTests {

    private func explainer(
        _ chat: ScriptedChat, language: String? = "de",
        configure: (inout Configuration) -> Void = { _ in }
    ) -> Explainer {
        var configuration = Configuration.default
        configuration.doNotTranslate = ["Otterbach"]
        configure(&configuration)
        return Explainer(
            configuration: configuration, chat: chat,
            recognizer: FixedRecognizer(code: language))
    }

    private let idiom = "Das ist nicht mein Bier."

    @Test("a reply becomes a summary with its notes")
    func explains() async throws {
        let chat = ScriptedChat([reply(
            "It is not my business.", [note("nicht mein Bier", "not my concern")])])
        let events = try await collect(explainer(chat).explain(UserText(idiom)))
        #expect(events.first == .started)
        let done = try #require(result(events))
        #expect(done.summary == "It is not my business.")
        #expect(done.notes == [ExplainNote(phrase: "nicht mein Bier", explanationEn: "not my concern")])
        #expect(done.warnings.isEmpty)
    }

    @Test("text detected as another language is refused, and nothing is sent")
    func refusesNonGerman() async throws {
        let chat = ScriptedChat([reply("x")])
        await #expect(throws: ExplanationFailure.notGerman) {
            _ = try await collect(explainer(chat, language: "en").explain(UserText("This is English.")))
        }
        #expect(chat.prompts.isEmpty)
    }

    @Test("text the detector cannot place is sent")
    func sendsWhenUnsure() async throws {
        let chat = ScriptedChat([reply("A greeting.")])
        _ = try await collect(explainer(chat, language: nil).explain(UserText("Moin")))
        #expect(chat.prompts.count == 1)
    }

    @Test("the request is one block, for the Explain model, terms masked, with the style note")
    func request() async throws {
        let chat = ScriptedChat([reply("A meeting.")])
        let text = "Wir treffen uns in Otterbach.\n\nBis bald."
        _ = try await collect(
            explainer(chat, configure: { $0.models[.explain] = "explain-model" })
                .explain(UserText(text), styleNote: "focus on grammar"))
        #expect(chat.models == ["explain-model"])
        let prompt = try #require(chat.prompts.first)
        #expect(prompt.contains("exactly 1 block"))
        #expect(prompt.contains(TokenProtector.sentinel(0)))
        #expect(!prompt.contains("in Otterbach"))
        #expect(prompt.contains("focus on grammar"))
    }

    @Test("the summary streams as it grows; the notes come only with the result")
    func streamsSummary() async throws {
        let chat = ScriptedChat([[
            #"{"summary_en": "The meet"#,
            #"ing starts"#,
            #" at ten.", "notes": [{"phrase": "um 10 Uhr", "explanation_en": "at ten"}]}"#,
        ]])
        let events = try await collect(explainer(chat).explain(UserText("Die Sitzung beginnt um 10 Uhr.")))
        #expect(summaries(events) == ["The meet", "The meeting starts", "The meeting starts at ten."])
        #expect(events.filter { $0 == .progress }.count == 3)
        let done = try #require(result(events))
        #expect(done.notes.count == 1)
    }

    @Test("masked terms come back in the summary, the phrases and the explanations")
    func restoresTerms() async throws {
        let s = TokenProtector.sentinel(0)
        let chat = ScriptedChat([reply("A meeting in \(s).", [note("in \(s)", "\(s) is a place")])])
        let events = try await collect(explainer(chat).explain(UserText("Wir treffen uns in Otterbach.")))
        let done = try #require(result(events))
        #expect(done.summary == "A meeting in Otterbach.")
        #expect(done.notes == [ExplainNote(phrase: "in Otterbach", explanationEn: "Otterbach is a place")])
        #expect(summaries(events).last == "A meeting in Otterbach.")
    }

    @Test("a term the explanation does not repeat is not a warning")
    func missingTermIsNoWarning() async throws {
        let chat = ScriptedChat([reply("A meeting somewhere.")])
        let done = try #require(result(try await collect(
            explainer(chat).explain(UserText("Wir treffen uns in Otterbach.")))))
        #expect(done.warnings.isEmpty)
    }

    @Test("a placeholder the model left behind is a warning")
    func debrisWarns() async throws {
        let chat = ScriptedChat([reply("A meeting in \u{27E6}DNT7\u{27E7}.")])
        let done = try #require(result(try await collect(explainer(chat).explain(UserText(idiom)))))
        #expect(done.warnings == ["The model left a placeholder behind; check the text before using it."])
    }

    @Test("English rules apply to the explanations; German phrases are quoted as returned")
    func localeRules() async throws {
        let chat = ScriptedChat([reply(
            "Gru\u{00DF} is a greeting.", [note("Gru\u{00DF}", "Gru\u{00DF} means greeting")])])
        let done = try #require(result(try await collect(
            explainer(chat).explain(UserText("Gru\u{00DF} aus Bern.")))))
        #expect(done.summary == "Gru\u{00DF} is a greeting.")
        #expect(done.notes == [ExplainNote(phrase: "Gru\u{00DF}", explanationEn: "Gru\u{00DF} means greeting")])
    }

    @Test("a note with an empty phrase or explanation is dropped")
    func dropsEmptyNotes() async throws {
        let chat = ScriptedChat([reply("Fine.", [note("", "x"), note("y", "  "), note("z", "w")])])
        let done = try #require(result(try await collect(explainer(chat).explain(UserText(idiom)))))
        #expect(done.notes == [ExplainNote(phrase: "z", explanationEn: "w")])
    }

    @Test("an empty summary is an unreadable reply")
    func emptySummary() async throws {
        let chat = ScriptedChat([reply("  ", [note("a", "b")])])
        await #expect(throws: ExplanationFailure.unreadableReply) {
            _ = try await collect(explainer(chat).explain(UserText(idiom)))
        }
    }

    @Test("a reply that is not the contract is an unreadable reply")
    func invalidJSON() async throws {
        let chat = ScriptedChat([["It means: not my business."]])
        await #expect(throws: ExplanationFailure.unreadableReply) {
            _ = try await collect(explainer(chat).explain(UserText(idiom)))
        }
    }

    @Test("an empty reply is reported as such")
    func emptyReply() async throws {
        let chat = ScriptedChat([["  "]])
        await #expect(throws: ExplanationFailure.emptyResponse) {
            _ = try await collect(explainer(chat).explain(UserText(idiom)))
        }
    }

    @Test("Copy takes the summary alone, or the summary and one line per note")
    func copyText() {
        #expect(ExplanationResult(summary: "S", notes: [], warnings: []).copyText == "S")
        let full = ExplanationResult(
            summary: "S",
            notes: [ExplainNote(phrase: "a", explanationEn: "b"), ExplainNote(phrase: "c", explanationEn: "d")],
            warnings: [])
        #expect(full.copyText == "S\n\n- \"a\": b\n- \"c\": d")
    }
}
