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

/// Answers a fixed language at a fixed confidence, so the gate is tested
/// without NaturalLanguage -- confident, below-floor and "no guess at all"
/// alike.
private struct FixedRecognizer: LanguageRecognizing {
    let code: String?
    var confidence: Double = 0.99
    func hypotheses(for text: String) -> [LanguageCode: Double] {
        guard let code else { return [:] }
        return [LanguageCode(code): confidence]
    }
}

private func collect(_ stream: LazyStream<CorrectionEvent>) async throws -> [CorrectionEvent] {
    var events: [CorrectionEvent] = []
    for try await event in stream { events.append(event) }
    return events
}

private func result(_ events: [CorrectionEvent]) -> CorrectionResult? {
    guard case .finished(let result) = events.last else { return nil }
    return result
}

private func reply(_ blocks: [String], _ errors: String = "[]") -> [String] {
    let quoted = blocks.map { "\"\($0)\"" }.joined(separator: ", ")
    return ["{\"corrected_blocks\": [\(quoted)], \"errors\": \(errors)}"]
}

private let genderError = """
    [{"original": "der Kollege", "corrected": "dem Kollegen", "category": "gender", \
    "explanation_en": "mit takes the dative", "severity": "error"}]
    """

@Suite("The corrector, from German text to a checked correction", .timeLimit(.minutes(1)))
struct CorrectorTests {

    private func corrector(
        _ chat: ScriptedChat, language: String? = "de", confidence: Double = 0.99,
        configure: (inout Configuration) -> Void = { _ in }
    ) -> Corrector {
        var configuration = Configuration.default
        configuration.doNotTranslate = ["Otterbach"]
        configure(&configuration)
        return Corrector(
            configuration: configuration, chat: chat,
            recognizer: FixedRecognizer(code: language, confidence: confidence))
    }

    private let long = "Ich habe gestern mit der Kollege gesprochen."

    @Test("a correction is diffed, itemised and checked")
    func corrects() async throws {
        let chat = ScriptedChat([reply(["Ich habe gestern mit dem Kollegen gesprochen."], genderError)])
        let events = try await collect(corrector(chat).correct(UserText(long), profile: .colleagues))
        #expect(events.first == .started)
        let done = try #require(result(events))
        #expect(done.corrected == UserText("Ich habe gestern mit dem Kollegen gesprochen."))
        #expect(done.errors.map(\.category) == [.gender])
        #expect(done.suggestions.isEmpty)
        #expect(done.warnings.isEmpty)
        #expect(!done.hasNoErrors)
        #expect(done.diff.contains(.removed("der")))
        #expect(done.diff.contains(.added("dem")))
    }

    @Test("an unchanged text is the no-errors result")
    func noErrors() async throws {
        let chat = ScriptedChat([reply([long])])
        let done = try #require(result(try await collect(
            corrector(chat).correct(UserText(long), profile: .colleagues))))
        #expect(done.hasNoErrors)
        #expect(done.diff == [.same(long)])
    }

    @Test("suggestions are separated from errors")
    func suggestionsSeparated() async throws {
        let suggestion = """
            [{"original": "gesprochen", "corrected": "geredet", "category": "register", \
            "explanation_en": "more casual", "severity": "suggestion"}]
            """
        let chat = ScriptedChat([reply([long], suggestion)])
        let done = try #require(result(try await collect(
            corrector(chat).correct(UserText(long), profile: .colleagues))))
        #expect(done.errors.isEmpty)
        #expect(done.suggestions.map(\.corrected) == ["geredet"])
        #expect(done.hasNoErrors)
    }

    @Test("text that is not German is refused before anything is sent")
    func notGerman() async {
        let chat = ScriptedChat([])
        await #expect(throws: CorrectionFailure.notGerman) {
            _ = try await collect(corrector(chat, language: "en")
                .correct(UserText("This is plainly English text."), profile: .colleagues))
        }
        #expect(chat.prompts.isEmpty)
    }

    @Test("text too short to judge is allowed through")
    func tooShortAllowed() async throws {
        let chat = ScriptedChat([reply(["Danke"])])
        _ = try await collect(corrector(chat, language: "en").correct(UserText("Danke"), profile: .colleagues))
        #expect(chat.prompts.count == 1)
    }

    @Test("a below-floor guess of another language is still refused")
    func belowFloorNonGermanRefused() async {
        let chat = ScriptedChat([])
        await #expect(throws: CorrectionFailure.notGerman) {
            _ = try await collect(corrector(chat, language: "en", confidence: 0.4)
                .correct(UserText(long), profile: .colleagues))
        }
        #expect(chat.prompts.isEmpty)
    }

    @Test("a below-floor guess of German is allowed through")
    func belowFloorGermanAllowed() async throws {
        let chat = ScriptedChat([reply([long])])
        _ = try await collect(corrector(chat, language: "de", confidence: 0.4)
            .correct(UserText(long), profile: .colleagues))
        #expect(chat.prompts.count == 1)
    }

    @Test("no hypothesis at all is allowed through")
    func noHypothesisAllowed() async throws {
        let chat = ScriptedChat([reply([long])])
        _ = try await collect(corrector(chat, language: nil).correct(UserText(long), profile: .colleagues))
        #expect(chat.prompts.count == 1)
    }

    @Test("an unreadable reply is a failure, never a correction")
    func unreadable() async {
        let chat = ScriptedChat([["Das sieht gut aus!"]])
        await #expect(throws: CorrectionFailure.unreadableReply) {
            _ = try await collect(corrector(chat).correct(UserText(long), profile: .colleagues))
        }
    }

    @Test("an empty reply is its own failure")
    func empty() async {
        let chat = ScriptedChat([[" "]])
        await #expect(throws: CorrectionFailure.emptyResponse) {
            _ = try await collect(corrector(chat).correct(UserText(long), profile: .colleagues))
        }
    }

    @Test("a wrong block count retries once with the whole text")
    func retries() async throws {
        let two = "Erste Zeile ist gut.\nZweite Zeile ist gut."
        let chat = ScriptedChat([reply(["nur eins"]), reply(["Erste Zeile ist gut.\\nZweite Zeile ist gut."])])
        let done = try #require(result(try await collect(
            corrector(chat).correct(UserText(two), profile: .colleagues))))
        #expect(chat.prompts.count == 2)
        #expect(chat.prompts[1].contains("exactly 1 block"))
        #expect(done.corrected == UserText(two))
    }

    @Test("structure lost twice is a failure, not a stitched text")
    func structureLost() async {
        let two = "Erste Zeile ist gut.\nZweite Zeile ist gut."
        let chat = ScriptedChat([reply(["eins"]), reply(["a", "b"])])
        await #expect(throws: CorrectionFailure.structureLost) {
            _ = try await collect(corrector(chat).correct(UserText(two), profile: .colleagues))
        }
        #expect(chat.prompts.count == 2)
    }

    @Test("an eszett in the user's own text becomes an explained spelling error")
    func eszett() async throws {
        let text = "Die Stra\u{00DF}e ist gesperrt heute."
        let chat = ScriptedChat([reply([text])])
        let done = try #require(result(try await collect(
            corrector(chat).correct(UserText(text), profile: .colleagues))))
        #expect(done.corrected == UserText("Die Strasse ist gesperrt heute."))
        #expect(done.errors.contains { $0.category == .spelling && $0.original == "\u{00DF}" })
        #expect(done.warnings.isEmpty)
        #expect(!done.hasNoErrors)
    }

    @Test("an eszett inside a protected term is never treated as the user's own spelling")
    func protectedTermEszettIgnored() async throws {
        let text = "Wei\u{00DF}enburg liegt im Norden."
        let chat = ScriptedChat([reply(["\u{27E6}DNT0\u{27E7} liegt im Norden."])])
        let done = try #require(result(try await collect(
            corrector(chat) { $0.doNotTranslate = ["Wei\u{00DF}enburg"] }
                .correct(UserText(text), profile: .colleagues))))
        #expect(done.hasNoErrors)
        #expect(done.warnings.isEmpty)
        #expect(!done.errors.contains { $0.category == .spelling })
    }

    @Test("the model's own eszett fix is not duplicated by a locale-rule row")
    func eszettFixNotDuplicated() async throws {
        let text = "Die Stra\u{00DF}e ist alt."
        let ownFix = """
            [{"original": "Stra\u{00DF}e", "corrected": "Strasse", "category": "spelling", \
            "explanation_en": "Swiss orthography", "severity": "error"}]
            """
        let chat = ScriptedChat([reply(["Die Strasse ist alt."], ownFix)])
        let done = try #require(result(try await collect(
            corrector(chat).correct(UserText(text), profile: .colleagues))))
        #expect(done.errors.count == 1)
        #expect(done.errors.first?.original == "Stra\u{00DF}e")
    }

    @Test("an unrelated item that merely contains \"ss\" does not suppress the eszett row")
    func unrelatedItemDoesNotSuppressEszettRow() async throws {
        let text = "mit der Stra\u{00DF}e ist gut und der Baum ist gro\u{00DF}."
        let unrelatedFix = """
            [{"original": "mit der Stra\u{00DF}e ist gut", \
            "corrected": "mit der Stra\u{00DF}e ist besser", "category": "register", \
            "explanation_en": "more natural wording", "severity": "error"}]
            """
        let chat = ScriptedChat([reply(
            ["mit der Stra\u{00DF}e ist besser und der Baum ist gro\u{00DF}."], unrelatedFix)])
        let done = try #require(result(try await collect(
            corrector(chat).correct(UserText(text), profile: .colleagues))))
        #expect(done.errors.count == 2)
        #expect(done.errors.contains { $0.category == .spelling && $0.original == "\u{00DF}" })
    }

    @Test("only one of two eszett words fixed still adds the row for the other")
    func partialEszettFixStillAddsRow() async throws {
        let text = "Die Stra\u{00DF}e ist alt und der Baum ist gro\u{00DF}."
        let ownFix = """
            [{"original": "Stra\u{00DF}e", "corrected": "Strasse", "category": "spelling", \
            "explanation_en": "Swiss orthography", "severity": "error"}]
            """
        let chat = ScriptedChat([reply(
            ["Die Strasse ist alt und der Baum ist gro\u{00DF}."], ownFix)])
        let done = try #require(result(try await collect(
            corrector(chat).correct(UserText(text), profile: .colleagues))))
        #expect(done.errors.count == 2)
        #expect(done.errors.contains { $0.category == .spelling && $0.original == "\u{00DF}" })
    }

    @Test("a listed fix's corrected fragment is shown without the eszett")
    func fixDisplaysWithoutEszett() async throws {
        let text = "Der Baum ist gross."
        let errors = """
            [{"original": "gross", "corrected": "gro\u{00DF}", "category": "spelling", \
            "explanation_en": "adjective form", "severity": "error"}]
            """
        let chat = ScriptedChat([reply(["Der Baum ist gross."], errors)])
        let done = try #require(result(try await collect(
            corrector(chat).correct(UserText(text), profile: .colleagues))))
        #expect(!done.errors.contains { $0.corrected.contains("\u{00DF}") })
    }

    @Test("a listed fix's corrected fragment keeps a protected term as written")
    func fixFragmentProtectsDNTTerm() async throws {
        let text = "Wei\u{00DF}enburg ist gro."
        let errors = """
            [{"original": "\u{27E6}DNT0\u{27E7} ist gro", \
            "corrected": "\u{27E6}DNT0\u{27E7} ist gro\u{00DF}", "category": "spelling", \
            "explanation_en": "adjective ending", "severity": "error"}]
            """
        let chat = ScriptedChat([reply(["\u{27E6}DNT0\u{27E7} ist gro\u{00DF}."], errors)])
        let done = try #require(result(try await collect(
            corrector(chat) { $0.doNotTranslate = ["Wei\u{00DF}enburg"] }
                .correct(UserText(text), profile: .colleagues))))
        #expect(done.errors.first?.corrected == "Wei\u{00DF}enburg ist gross")
    }

    @Test("protected terms come back inside the text and the fragments")
    func sentinels() async throws {
        let text = "Otterbach hat der Kollege gesehen."
        let error = """
            [{"original": "\u{27E6}DNT0\u{27E7} hat der", "corrected": "\u{27E6}DNT0\u{27E7} hat den", \
            "category": "case", "explanation_en": "accusative", "severity": "error"}]
            """
        let chat = ScriptedChat([reply(["\u{27E6}DNT0\u{27E7} hat den Kollegen gesehen."], error)])
        let done = try #require(result(try await collect(
            corrector(chat).correct(UserText(text), profile: .colleagues))))
        #expect(done.corrected == UserText("Otterbach hat den Kollegen gesehen."))
        #expect(done.errors.first?.original == "Otterbach hat der")
        #expect(!chat.prompts[0].contains("Otterbach hat"))
    }

    @Test("the preview is post-processed")
    func preview() async throws {
        let chat = ScriptedChat([[
            "{\"corrected_blocks\": [\"Die Stra", "\u{00DF}e ist gesperrt heute.\"], \"errors\": []}",
        ]])
        let events = try await collect(corrector(chat).correct(
            UserText("Die Strasse ist gesperrt heute."), profile: .colleagues))
        let previews = events.compactMap { event -> String? in
            guard case .preview(let text) = event else { return nil }
            return text.value
        }
        #expect(!previews.isEmpty)
        #expect(previews.allSatisfy { !$0.contains("\u{00DF}") })
    }

    @Test("the prompt carries the register and the style note")
    func promptContents() async throws {
        let chat = ScriptedChat([reply([long])])
        _ = try await collect(corrector(chat).correct(
            UserText(long), profile: .administration, styleNote: "streng"))
        #expect(chat.prompts[0].contains("\"Sie\""))
        #expect(chat.prompts[0].contains("streng"))
        #expect(chat.prompts[0].contains("corrected_blocks applies only"))
    }

    @Test("the configured correct model is the one asked")
    func model() async throws {
        let chat = ScriptedChat([reply([long])])
        _ = try await collect(corrector(chat) { $0.models[.correct] = "tiny:1b" }
            .correct(UserText(long), profile: .colleagues))
        #expect(chat.models == ["tiny:1b"])
    }

    @Test("building a correction sends nothing until it is iterated")
    func lazy() {
        let chat = ScriptedChat([reply([long])])
        _ = corrector(chat).correct(UserText(long), profile: .colleagues)
        #expect(chat.prompts.isEmpty)
    }

    @Test("cancelling a correction reaches the chat stream")
    func cancellation() async throws {
        final class Endless: ChatStreaming, @unchecked Sendable {
            private let lock = NSLock()
            private var ended = false
            var terminated: Bool { lock.lock(); defer { lock.unlock() }; return ended }
            func chat(model: String, messages: [ChatMessage]) -> LazyStream<StreamEvent> {
                LazyStream { [self] in
                    AsyncThrowingStream { continuation in
                        continuation.yield(.delta("{"))
                        continuation.onTermination = { _ in
                            self.lock.lock(); self.ended = true; self.lock.unlock()
                        }
                    }
                }
            }
        }
        let chat = Endless()
        let subject = Corrector(
            configuration: .default, chat: chat, recognizer: FixedRecognizer(code: "de"))
        let consumer = Task {
            for try await _ in subject.correct(UserText(long), profile: .colleagues) {}
        }
        try await Task.sleep(for: .milliseconds(50))
        consumer.cancel()
        var waited = 0
        while !chat.terminated && waited < 100 {
            try await Task.sleep(for: .milliseconds(5))
            waited += 1
        }
        #expect(chat.terminated)
    }
}
