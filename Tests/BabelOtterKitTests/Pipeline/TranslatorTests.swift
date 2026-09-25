import Foundation
import Testing

@testable import BabelOtterKit

/// Replies scripted per call, recording what was asked.
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

private let open = "\u{27E6}"
private let close = "\u{27E7}"
private let german = LanguageConfig.swissGerman.code
private let english = LanguageConfig.english.code

private func collect(_ stream: LazyStream<TranslationEvent>) async throws -> [TranslationEvent] {
    var events: [TranslationEvent] = []
    for try await event in stream { events.append(event) }
    return events
}

private func result(_ events: [TranslationEvent]) -> TranslationResult? {
    guard case .finished(let result) = events.last else { return nil }
    return result
}

@Suite("The translator, from selected text to finished translation")
struct TranslatorTests {

    private func translator(
        _ chat: ScriptedChat, configure: (inout Configuration) -> Void = { _ in }
    ) -> Translator {
        var configuration = Configuration.default
        configuration.doNotTranslate = ["Otterbach"]
        configure(&configuration)
        return Translator(configuration: configuration, chat: chat)
    }

    @Test("a German list becomes an English list with its terms and markers intact")
    func germanListToEnglish() async throws {
        let chat = ScriptedChat([[
            "{\"blocks\": [\"The street", " is big\", \"\(open)DNT0\(close) is a school\"]}",
        ]])
        let events = try await collect(translator(chat).translate(
            UserText("- Die Strasse ist gross\n- Otterbach ist eine Schule"),
            direction: Direction(source: german, target: english), profile: .colleagues))

        #expect(events.first == .started(Direction(source: german, target: english)))
        let finished = try #require(result(events))
        #expect(finished.text == UserText("- The street is big\n- Otterbach is a school"))
        #expect(finished.warnings.isEmpty)
        #expect(chat.prompts.count == 1)
        #expect(chat.prompts[0].contains("exactly 2 block"))
        #expect(!chat.prompts[0].contains("Otterbach ist"), "the protected term must be masked")
    }

    @Test("the preview grows as the reply arrives, and is post-processed")
    func previewIsPostProcessed() async throws {
        let chat = ScriptedChat([[
            "{\"blocks\": [\"Die Stra", "\u{00DF}e ist gro", "\u{00DF}\"]}",
        ]])
        let events = try await collect(translator(chat).translate(
            UserText("The street is big"),
            direction: Direction(source: english, target: german), profile: .colleagues))

        let previews = events.compactMap { event -> String? in
            guard case .preview(let text) = event else { return nil }
            return text.value
        }
        #expect(previews.count >= 2)
        #expect(previews.allSatisfy { !$0.contains("\u{00DF}") }, "FR-TRN-05 holds in the preview too")
        #expect(result(events)?.text == UserText("Die Strasse ist gross"))
    }

    @Test("a wrong block count retries once with the whole text")
    func retriesWholeText() async throws {
        let chat = ScriptedChat([
            ["{\"blocks\": [\"only one\"]}"],
            ["{\"blocks\": [\"Erste Zeile.\\nZweite Zeile.\"]}"],
        ])
        let events = try await collect(translator(chat).translate(
            UserText("First line.\nSecond line."),
            direction: Direction(source: english, target: german), profile: .colleagues))

        #expect(chat.prompts.count == 2)
        #expect(chat.prompts[1].contains("exactly 1 block"))
        let finished = try #require(result(events))
        #expect(finished.text == UserText("Erste Zeile.\nZweite Zeile."))
        #expect(finished.warnings.isEmpty)
    }

    @Test("a second wrong count degrades with a warning instead of retrying again")
    func degradesAfterOneRetry() async throws {
        let chat = ScriptedChat([
            ["{\"blocks\": [\"one\"]}"],
            ["{\"blocks\": [\"eins\", \"zwei\"]}"],
        ])
        let events = try await collect(translator(chat).translate(
            UserText("First line.\nSecond line."),
            direction: Direction(source: english, target: german), profile: .colleagues))

        #expect(chat.prompts.count == 2, "never more than one retry")
        let finished = try #require(result(events))
        #expect(finished.text == UserText("eins\nzwei"))
        #expect(!finished.warnings.isEmpty)
    }

    @Test("an unparseable reply is shown as it came, with the locale rules applied")
    func unparseableReply() async throws {
        let chat = ScriptedChat([["Die Stra\u{00DF}e ist gro\u{00DF}."]])
        let events = try await collect(translator(chat).translate(
            UserText("The street is big."),
            direction: Direction(source: english, target: german), profile: .colleagues))

        let finished = try #require(result(events))
        #expect(finished.text == UserText("Die Strasse ist gross."))
        #expect(!finished.warnings.isEmpty)
    }

    @Test("a mangled sentinel becomes a warning")
    func mangledSentinel() async throws {
        let chat = ScriptedChat([["{\"blocks\": [\"The school is good\"]}"]])
        let events = try await collect(translator(chat).translate(
            UserText("Otterbach ist gut"),
            direction: Direction(source: german, target: english), profile: .colleagues))
        #expect(result(events)?.warnings.contains { $0.contains("Otterbach") } == true)
    }

    @Test("an empty reply is an error, not an empty translation")
    func emptyReply() async {
        let chat = ScriptedChat([["  "]])
        await #expect(throws: TranslationError.emptyResponse) {
            _ = try await collect(translator(chat).translate(
                UserText("Hello there"),
                direction: Direction(source: english, target: german), profile: .colleagues))
        }
    }

    @Test("a language that is not configured is refused before anything is sent")
    func unconfiguredLanguage() async {
        let chat = ScriptedChat([])
        let french = LanguageCode("fr")
        await #expect(throws: TranslationError.languageNotConfigured(french)) {
            _ = try await collect(translator(chat).translate(
                UserText("Bonjour"),
                direction: Direction(source: french, target: english), profile: .colleagues))
        }
        #expect(chat.prompts.isEmpty)
    }

    @Test("the configured translate model is the one asked")
    func usesConfiguredModel() async throws {
        let chat = ScriptedChat([["{\"blocks\": [\"x\"]}"]])
        _ = try await collect(translator(chat) { $0.models[.translate] = "tiny:1b" }.translate(
            UserText("Hello"),
            direction: Direction(source: english, target: german), profile: .colleagues))
        #expect(chat.models == ["tiny:1b"])
    }

    @Test("building a translation sends nothing until it is iterated")
    func lazy() {
        let chat = ScriptedChat([["{\"blocks\": [\"x\"]}"]])
        _ = translator(chat).translate(
            UserText("secret"),
            direction: Direction(source: english, target: german), profile: .colleagues)
        #expect(chat.prompts.isEmpty, "NFR-P1: constructing must not transmit")
    }

    @Test("a long German selection resolves to German into English")
    func directionForGerman() {
        let text = UserText(
            "Der Ausschuss hat beschlossen, die Entscheidung bis zur naechsten Sitzung zu "
                + "verschieben, weil die Zahlen noch nicht vorliegen.")
        #expect(translator(ScriptedChat([])).direction(for: text)
            == .success(Direction(source: german, target: english)))
    }

    @Test("a selection too short to judge asks, offering every enabled language")
    func directionTooShort() {
        #expect(translator(ScriptedChat([])).direction(for: UserText("Hallo"))
            == .failure(.directionUnknown(candidates: [english, german])))
    }

    @Test("choosing a target picks the other enabled language as the source")
    func directionInto() {
        let subject = translator(ScriptedChat([]))
        #expect(subject.direction(into: english) == Direction(source: german, target: english))
        #expect(subject.direction(into: german) == Direction(source: english, target: german))
        #expect(subject.direction(into: LanguageCode("fr")) == nil)
    }

    @Test("swapping reverses the direction")
    func swap() {
        #expect(Direction(source: german, target: english).swapped
            == Direction(source: english, target: german))
    }
}
