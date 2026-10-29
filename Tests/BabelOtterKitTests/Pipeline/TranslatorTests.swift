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

/// Records whether its own stream was told the consumer is gone, mirroring
/// `OllamaClientTests`' recorder -- standing in for "the chat stream was
/// actually stopped" without depending on a real transport.
private final class TerminationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var isTerminated = false

    func markTerminated() {
        lock.lock()
        isTerminated = true
        lock.unlock()
    }

    private var terminated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isTerminated
    }

    /// Polls in short steps rather than sleeping a fixed duration: fast when
    /// termination already landed, bounded when it never does.
    func waitForTermination(timeoutNanoseconds: UInt64 = 500_000_000) async -> Bool {
        let step: UInt64 = 5_000_000
        var waited: UInt64 = 0
        while waited < timeoutNanoseconds {
            if terminated { return true }
            try? await Task.sleep(nanoseconds: step)
            waited += step
        }
        return terminated
    }
}

/// A chat stream that yields once and then never finishes on its own --
/// exactly what a generation in flight looks like from `Translator`'s side.
/// Only cancellation can end it; this is how the test proves cancelling a
/// translation reaches the chat stream, not just the caller.
private final class NeverEndingChat: ChatStreaming, @unchecked Sendable {
    let recorder = TerminationRecorder()

    func chat(model: String, messages: [ChatMessage]) -> LazyStream<StreamEvent> {
        LazyStream { [recorder] in
            AsyncThrowingStream { continuation in
                continuation.onTermination = { _ in recorder.markTerminated() }
                continuation.yield(.delta("a"))
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

private func audiences(_ events: [TranslationEvent]) -> [TranslationEvent] {
    events.filter { event in
        guard case .audience = event else { return false }
        return true
    }
}

private func index(of wanted: (TranslationEvent) -> Bool, in events: [TranslationEvent]) -> Int? {
    events.firstIndex(where: wanted)
}

private let inferring = AudienceRequest.infer(profiles: AudienceProfile.shippedDefaults, fallback: .colleagues)

/// `.timeLimit`: muter has no per-mutant timeout, and a mutant that deletes a
/// `continuation.finish()` leaves every stream here open forever. Without a
/// limit one such mutant stalls the whole mutation job until CI cancels it,
/// which is what happened to every run from the M1a shell onward. With it,
/// the hang is a failure -- a killed mutant -- after a minute.
@Suite("The translator, from selected text to finished translation", .timeLimit(.minutes(1)))
struct TranslatorTests {

    private func translator(
        _ chat: ScriptedChat, configure: (inout Configuration) -> Void = { _ in }
    ) -> Translator {
        var configuration = Configuration.default
        configuration.doNotTranslate = ["Otterbach"]
        configure(&configuration)
        return Translator(configuration: configuration, chat: chat)
    }

    @Test("an inferred audience is reported once, before the result, and carried by it")
    func inferredAudience() async throws {
        let chat = ScriptedChat([[
            "{\"detected_audience\": \"students\", \"audience_evidence\": \"Dear students\", \"blocks\": [\"Hallo\"]}",
        ]])
        let events = try await collect(translator(chat).translate(
            UserText("Dear students, hello"), direction: Direction(source: english, target: german),
            audience: inferring))

        #expect(audiences(events) == [.audience(.students, inferred: true)])
        let reported = try #require(index(of: { $0 == .audience(.students, inferred: true) }, in: events))
        #expect(reported < events.count - 1)
        let finished = try #require(result(events))
        #expect(finished.audience == .students)
        #expect(finished.audienceInferred)
        #expect(chat.prompts[0].contains("Decide which of these audiences"))
    }

    @Test("the audience is reported as soon as it arrives, before the text")
    func audienceBeforeText() async throws {
        let chat = ScriptedChat([[
            "{\"detected_audience\": \"students\", \"audience_evidence\": \"Dear students\", \"blocks\": [\"Hal",
            "lo\"]}",
        ]])
        let events = try await collect(translator(chat).translate(
            UserText("Dear students, hello"), direction: Direction(source: english, target: german),
            audience: inferring))

        let reported = try #require(index(of: { $0 == .audience(.students, inferred: true) }, in: events))
        let firstPreview = try #require(index(of: { event in
            guard case .preview = event else { return false }
            return true
        }, in: events))
        #expect(reported < firstPreview)
    }

    @Test("an audience without evidence is not a guess: the fallback")
    func noEvidenceFallsBack() async throws {
        let chat = ScriptedChat([["{\"detected_audience\": \"administration\", \"audience_evidence\": \"\", \"blocks\": [\"Hallo\"]}"]])
        let events = try await collect(translator(chat).translate(
            UserText("The room is closed on Friday."), direction: Direction(source: english, target: german),
            audience: inferring))

        #expect(audiences(events) == [.audience(.colleagues, inferred: false)])
    }

    @Test("evidence the text does not contain is not a guess either")
    func evidenceNotInTextFallsBack() async throws {
        let chat = ScriptedChat([[
            "{\"detected_audience\": \"administration\", \"audience_evidence\": \"Dear office\", \"blocks\": [\"Hallo\"]}",
        ]])
        let events = try await collect(translator(chat).translate(
            UserText("The room is closed on Friday."), direction: Direction(source: english, target: german),
            audience: inferring))

        #expect(audiences(events) == [.audience(.colleagues, inferred: false)])
    }

    @Test("the early report waits for the evidence, then reports at once")
    func earlyReportWaitsForEvidence() async throws {
        let chat = ScriptedChat([[
            "{\"detected_audience\": \"students\", ",
            "\"audience_evidence\": \"Dear students\", \"blocks\": [\"Hal",
            "lo\"]}",
        ]])
        let events = try await collect(translator(chat).translate(
            UserText("Dear students, hello"), direction: Direction(source: english, target: german),
            audience: inferring))

        let reported = try #require(index(of: { $0 == .audience(.students, inferred: true) }, in: events))
        let progress = events.prefix(reported).filter { $0 == .progress }.count
        // Each piece is read before its own progress event, so a report on
        // the second piece follows exactly one; on the first, none.
        #expect(progress == 1, "on the second piece, which completes the evidence")
        #expect(audiences(events).count == 1)
    }

    @Test("unclear means the fallback, not presented as inferred")
    func unclearFallsBack() async throws {
        let chat = ScriptedChat([["{\"detected_audience\": \"unclear\", \"blocks\": [\"Hallo\"]}"]])
        let events = try await collect(translator(chat).translate(
            UserText("Hello"), direction: Direction(source: english, target: german), audience: inferring))

        #expect(audiences(events) == [.audience(.colleagues, inferred: false)])
        #expect(result(events)?.audienceInferred == false)
    }

    @Test("the model naming the fallback is still an inference")
    func fallbackNamedExplicitly() async throws {
        let chat = ScriptedChat([[
            "{\"detected_audience\": \"colleagues\", \"audience_evidence\": \"Hi Anna\", \"blocks\": [\"Hallo\"]}",
        ]])
        let events = try await collect(translator(chat).translate(
            UserText("Hi Anna, hello"), direction: Direction(source: english, target: german),
            audience: inferring))

        #expect(audiences(events) == [.audience(.colleagues, inferred: true)])
    }

    @Test("a reply without the field falls back, still before the result")
    func missingFieldFallsBackBeforeFinished() async throws {
        let chat = ScriptedChat([["{\"blocks\": [\"Hallo\"]}"]])
        let events = try await collect(translator(chat).translate(
            UserText("Hello"), direction: Direction(source: english, target: german), audience: inferring))

        #expect(audiences(events) == [.audience(.colleagues, inferred: false)])
        let reported = try #require(index(of: { $0 == .audience(.colleagues, inferred: false) }, in: events))
        #expect(reported == events.count - 2)
    }

    @Test("an unparseable reply falls back, before the result")
    func unparseableFallsBack() async throws {
        let chat = ScriptedChat([["Hallo, no JSON"]])
        let events = try await collect(translator(chat).translate(
            UserText("Hello"), direction: Direction(source: english, target: german), audience: inferring))

        #expect(audiences(events) == [.audience(.colleagues, inferred: false)])
        #expect(result(events)?.audience == .colleagues)
    }

    @Test("the whole-text retry writes for the reported audience, fixed")
    func retryIsFixed() async throws {
        let chat = ScriptedChat([
            ["{\"detected_audience\": \"students\", \"audience_evidence\": \"Dear students\", \"blocks\": [\"only one\"]}"],
            ["{\"blocks\": [\"Erste Zeile.\\nZweite Zeile.\"]}"],
        ])
        let events = try await collect(translator(chat).translate(
            UserText("Dear students.\nSecond line."),
            direction: Direction(source: english, target: german), audience: inferring))

        #expect(chat.prompts.count == 2)
        #expect(!chat.prompts[1].contains("Decide which"))
        #expect(chat.prompts[1].contains("Audience: Students."))
        #expect(audiences(events) == [.audience(.students, inferred: true)])
        #expect(result(events)?.audience == .students)
    }

    @Test("a fixed audience is reported at once, as not inferred")
    func fixedIsReportedAtOnce() async throws {
        let chat = ScriptedChat([["{\"blocks\": [\"Hallo\"]}"]])
        let events = try await collect(translator(chat).translate(
            UserText("Hello"), direction: Direction(source: english, target: german), profile: .administration))

        #expect(events.count > 1)
        #expect(events[1] == .audience(.administration, inferred: false))
        #expect(audiences(events).count == 1)
        #expect(!chat.prompts[0].contains("Decide which"))
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

    @Test("an unparseable reply still restores a protected term")
    func unparseableReplyRestoresProtectedTerm() async throws {
        let chat = ScriptedChat([["\(open)DNT0\(close) is good, sorry no JSON"]])
        let events = try await collect(translator(chat).translate(
            UserText("Otterbach ist gut"),
            direction: Direction(source: german, target: english), profile: .colleagues))

        let finished = try #require(result(events))
        #expect(finished.text == UserText("Otterbach is good, sorry no JSON"))
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
        let dutch = LanguageCode("nl")
        await #expect(throws: TranslationError.languageNotConfigured(dutch)) {
            _ = try await collect(translator(chat).translate(
                UserText("Goedemorgen"),
                direction: Direction(source: dutch, target: english), profile: .colleagues))
        }
        #expect(chat.prompts.isEmpty)
    }

    @Test("every piece of the reply is reported as progress")
    func progress() async throws {
        let chat = ScriptedChat([["{\"blocks\": [\"x", "y\"]", "}"]])
        let events = try await collect(translator(chat).translate(
            UserText("Hello"),
            direction: Direction(source: english, target: german), profile: .colleagues))
        #expect(events.filter { $0 == .progress }.count == 3)
    }

    @Test("the configured translate model is the one asked")
    func usesConfiguredModel() async throws {
        let chat = ScriptedChat([["{\"blocks\": [\"x\"]}"]])
        _ = try await collect(translator(chat) { $0.models[.translate] = "tiny:1b" }.translate(
            UserText("Hello"),
            direction: Direction(source: english, target: german), profile: .colleagues))
        #expect(chat.models == ["tiny:1b"])
    }

    @Test("a style note reaches the prompt, on the retry too")
    func styleNoteReachesEveryPrompt() async throws {
        let chat = ScriptedChat([
            ["{\"blocks\": [\"only one\"]}"],
            ["{\"blocks\": [\"Erste Zeile.\\nZweite Zeile.\"]}"],
        ])
        _ = try await collect(translator(chat).translate(
            UserText("First line.\nSecond line."),
            direction: Direction(source: english, target: german), profile: .colleagues,
            styleNote: "use Sie"))
        #expect(chat.prompts.count == 2)
        #expect(chat.prompts.allSatisfy { $0.contains("use Sie") })
    }

    @Test("no style note, no style section")
    func noStyleNote() async throws {
        let chat = ScriptedChat([["{\"blocks\": [\"x\"]}"]])
        _ = try await collect(translator(chat).translate(
            UserText("Hello"),
            direction: Direction(source: english, target: german), profile: .colleagues))
        #expect(!chat.prompts[0].contains("Additional instruction"))
    }

    @Test("the profile's register reaches the prompt")
    func profileRegisterReachesPrompt() async throws {
        let chat = ScriptedChat([["{\"blocks\": [\"x\"]}"], ["{\"blocks\": [\"x\"]}"]])
        let subject = translator(chat)
        _ = try await collect(subject.translate(
            UserText("Hello"),
            direction: Direction(source: english, target: german), profile: .administration))
        _ = try await collect(subject.translate(
            UserText("Hello"),
            direction: Direction(source: english, target: german), profile: .colleagues))
        #expect(chat.prompts[0].contains("\"Sie\""))
        #expect(chat.prompts[1].contains("\"du\""))
    }

    /// A generation the consumer stopped listening to (Escape, a timeout)
    /// must not keep running underneath. `Translator.translate` wires its own
    /// `Task` to `continuation.onTermination`; without it, cancelling the
    /// caller never reaches the chat stream at all.
    @Test("cancelling a translation reaches the chat stream")
    func cancellingTranslationStopsTheChatStream() async throws {
        let chat = NeverEndingChat()
        let neverEnding = Translator(configuration: Configuration.default, chat: chat)

        let task = Task {
            var iterator = neverEnding.translate(
                UserText("Hello"),
                direction: Direction(source: english, target: german), profile: .colleagues
            ).makeAsyncIterator()
            _ = try? await iterator.next()  // .started, emitted before the chat stream runs
            _ = try? await iterator.next()  // parks here until cancelled
        }

        // Let the consuming task actually reach the parked await before
        // cancelling it, so cancellation lands mid-stream rather than before
        // anything began.
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()

        let terminated = await chat.recorder.waitForTermination()
        #expect(terminated, "cancelling the consumer must reach the chat stream, not leave it running")
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
            == .failure(.directionUnknown(source: nil, candidates: [english, german])))
    }

    @Test("with two languages, a target picked without a source comes from the other one")
    func directionInto() {
        let subject = translator(ScriptedChat([]))
        #expect(subject.direction(from: nil, into: english) == Direction(source: german, target: english))
        #expect(subject.direction(from: nil, into: german) == Direction(source: english, target: german))
        #expect(subject.direction(from: nil, into: LanguageCode("nl")) == nil)
        // French ships switched off: not a target.
        #expect(subject.direction(from: nil, into: LanguageCode("fr")) == nil)
    }

    /// English, de-CH, French and Italian on (#81); Spanish (#132) stays off.
    private func allFour(_ configuration: inout Configuration) {
        for index in configuration.languages.indices {
            let isSpanish = configuration.languages[index].code == LanguageConfig.spanish.code
            configuration.languages[index].enabled = !isSpanish
        }
    }

    private let french = LanguageCode("fr")
    private let italian = LanguageCode("it")

    @Test("a picked target is translated from the given source (#81)")
    func directionFromInto() {
        let subject = translator(ScriptedChat([]), configure: allFour)
        #expect(subject.direction(from: french, into: italian) == Direction(source: french, target: italian))
        #expect(subject.direction(from: french, into: french) == nil)
        #expect(subject.direction(from: LanguageCode("nl"), into: italian) == nil)
        // Without a source and with more than two languages, the source cannot be known.
        #expect(subject.direction(from: nil, into: italian) == nil)
        let twoOn = translator(ScriptedChat([]))
        #expect(twoOn.direction(from: french, into: english) == nil, "French is switched off")
    }

    @Test("a French paragraph with four languages asks for the target, carrying French")
    func directionFrenchFour() {
        let text = UserText(
            "Le comité a décidé de reporter la décision à la prochaine séance, "
                + "lorsque les chiffres révisés du budget seront enfin disponibles.")
        let subject = translator(ScriptedChat([]), configure: allFour)
        #expect(subject.direction(for: text)
            == .failure(.directionUnknown(source: french, candidates: [english, german, italian])))
        #expect(subject.direction(for: text, remembered: [french: german])
            == .success(Direction(source: french, target: german)))
    }

    @Test("a named source settles the target from memory, or offers the others")
    func directionFromNamedSource() {
        let subject = translator(ScriptedChat([]), configure: allFour)
        #expect(subject.direction(from: italian, remembered: [italian: english])
            == .success(Direction(source: italian, target: english)))
        #expect(subject.direction(from: italian)
            == .failure(.directionUnknown(source: italian, candidates: [english, german, french])))
        let twoOn = translator(ScriptedChat([]))
        #expect(twoOn.direction(from: german) == .success(Direction(source: german, target: english)))
    }

    @Test("swapping reverses the direction")
    func swap() {
        #expect(Direction(source: german, target: english).swapped
            == Direction(source: english, target: german))
    }
}
