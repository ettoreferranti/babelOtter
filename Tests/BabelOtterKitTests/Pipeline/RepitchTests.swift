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
    var confidence: Double = 0.99
    func hypotheses(for text: String) -> [LanguageCode: Double] {
        guard let code else { return [:] }
        return [LanguageCode(code): confidence]
    }
}

private func collect(_ stream: LazyStream<TranslationEvent>) async throws -> [TranslationEvent] {
    var events: [TranslationEvent] = []
    for try await event in stream { events.append(event) }
    return events
}

private func result(_ events: [TranslationEvent]) -> TranslationResult? {
    guard case .finished(let result) = events.last else { return nil }
    return result
}

private func reply(_ blocks: [String]) -> [String] {
    let quoted = blocks.map { "\"\($0)\"" }.joined(separator: ", ")
    return ["{\"blocks\": [\(quoted)]}"]
}

private let german = LanguageConfig.swissGerman.code
private let english = LanguageConfig.english.code

@Suite("Re-pitch: the same text, the same language, another audience", .timeLimit(.minutes(1)))
struct RepitchTests {

    private func translator(
        _ chat: ScriptedChat, detected: String? = "de", confidence: Double = 0.99,
        configure: (inout Configuration) -> Void = { _ in }
    ) -> Translator {
        var configuration = Configuration.default
        configuration.doNotTranslate = ["Otterbach"]
        configure(&configuration)
        return Translator(
            configuration: configuration, chat: chat,
            recognizer: FixedRecognizer(code: detected, confidence: confidence))
    }

    private let draft = UserText("Hallo Thomas, kannst du das bis Freitag schicken?")

    @Test("the text's language is the enabled language detected, by base subtag")
    func languageDetected() {
        #expect(translator(ScriptedChat([])).language(for: draft) == .success(german))
        #expect(translator(ScriptedChat([]), detected: "en").language(for: draft) == .success(english))
    }

    @Test("with three languages enabled the text's language is still found")
    func languageAmongThree() {
        let french = LanguageConfig(code: LanguageCode("fr"), displayName: "French", localeRules: [], enabled: true)
        let found = translator(ScriptedChat([]), configure: { $0.languages.append(french) }).language(for: draft)
        #expect(found == .success(german))
    }

    @Test("a language not enabled is reported")
    func languageNotEnabled() {
        #expect(translator(ScriptedChat([]), detected: "fr").language(for: draft)
            == .failure(.languageNotConfigured(LanguageCode("fr"))))
    }

    @Test("an undecided detection offers the enabled languages")
    func languageUndecided() {
        let configuration = Configuration.default
        #expect(translator(ScriptedChat([]), detected: nil).language(for: draft)
            == .failure(.directionUnknown(candidates: configuration.enabledLanguages.map(\.code))))
        #expect(translator(ScriptedChat([]), detected: "en", confidence: 0.3).language(for: draft)
            == .failure(.directionUnknown(candidates: configuration.enabledLanguages.map(\.code))))
    }

    @Test("the prompt is Re-pitch's, for the fixed audience, to the Re-pitch model, without the glossary")
    func prompt() async throws {
        let chat = ScriptedChat([reply(["Guten Tag Herr Meier"])])
        let configured = translator(chat, configure: {
            $0.models[.repitch] = "repitch-model"
            $0.glossary.concepts = [GlossaryConcept(
                terms: [LanguageCode("en"): "degree programme", german: "Studiengang"])]
        })
        _ = try await collect(configured.repitch(
            draft, language: german, audience: .administration, styleNote: "shorter"))
        #expect(chat.models == ["repitch-model"])
        let prompt = try #require(chat.prompts.first)
        #expect(prompt.contains("Rewrite the numbered blocks below"))
        #expect(prompt.contains("Language: Swiss Standard German."))
        #expect(prompt.contains("Audience: Administration."))
        #expect(!prompt.contains("degree programme"))
        #expect(!prompt.contains("Audiences (id"))
        #expect(prompt.contains("shorter"))
    }

    @Test("layout survives, de-CH rules apply, and a blocks-only reply is no format warning")
    func layoutAndRules() async throws {
        let chat = ScriptedChat([reply(["Guten Tag Herr Meier", "Mit freundlichen Gr\u{00FC}\u{00DF}en"])])
        let events = try await collect(translator(chat).repitch(
            UserText("Hallo Thomas\n\nLiebe Gr\u{00FC}sse"), language: german, audience: .administration))
        let done = try #require(result(events))
        #expect(done.text == UserText("Guten Tag Herr Meier\n\nMit freundlichen Gr\u{00FC}ssen"))
        #expect(done.warnings.isEmpty)
        #expect(done.direction == Direction(source: german, target: german))
    }

    @Test("protected terms come back")
    func protectedTerms() async throws {
        let s = TokenProtector.sentinel(0)
        let chat = ScriptedChat([reply(["Wir sehen uns in \(s)."])])
        let done = try #require(result(try await collect(translator(chat).repitch(
            UserText("Bis bald in Otterbach."), language: german, audience: .students))))
        #expect(done.text == UserText("Wir sehen uns in Otterbach."))
    }

    @Test("the audience is reported once, as fixed")
    func audienceFixed() async throws {
        let chat = ScriptedChat([reply(["Guten Tag"])])
        let events = try await collect(translator(chat).repitch(
            UserText("Hallo zusammen"), language: german, audience: .administration))
        let reported = events.filter { event in
            guard case .audience = event else { return false }
            return true
        }
        #expect(reported == [.audience(.administration, inferred: false)])
    }

    @Test("a wrong block count retries the whole text, still as a re-pitch")
    func retry() async throws {
        // "\\n": the newline must reach the reply as a JSON escape.
        let chat = ScriptedChat([reply(["one"]), reply(["Guten Tag\\n\\nBis bald"])])
        let done = try #require(result(try await collect(translator(chat).repitch(
            UserText("Hallo\n\nTsch\u{00FC}ss"), language: german, audience: .administration))))
        #expect(chat.prompts.count == 2)
        #expect(chat.prompts[1].contains("Rewrite the numbered blocks below"))
        #expect(done.text == UserText("Guten Tag\n\nBis bald"))
    }

    @Test("a fact the re-pitch lost is a warning")
    func lostFact() async throws {
        let chat = ScriptedChat([reply(["Treffen am 12.11.2026."])])
        let done = try #require(result(try await collect(translator(chat).repitch(
            UserText("Treffen am 12.11.2026 um 14:30."), language: german, audience: .administration))))
        #expect(done.warnings == ["\"14:30\" from the original is not in the re-pitch."])
    }

    @Test("Translate never runs the fact check")
    func translateUnchecked() async throws {
        let chat = ScriptedChat([["{\"detected_source\": \"de\", \"blocks\": [\"Meeting on 12.11.2026.\"]}"]])
        let done = try #require(result(try await collect(translator(chat).translate(
            UserText("Treffen am 12.11.2026 um 14:30."),
            direction: Direction(source: german, target: english), profile: .colleagues))))
        #expect(done.warnings.isEmpty)
    }
}
