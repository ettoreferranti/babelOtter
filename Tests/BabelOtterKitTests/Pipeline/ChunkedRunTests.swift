import Foundation
import Testing

@testable import BabelOtterKit

private final class ScriptedChat: ChatStreaming, @unchecked Sendable {
    private var replies: [[String]]
    private(set) var prompts: [String] = []
    init(_ replies: [[String]]) { self.replies = replies }
    func chat(model: String, messages: [ChatMessage]) -> LazyStream<StreamEvent> {
        LazyStream { [self] in
            prompts.append(messages.map(\.content).joined(separator: "\n"))
            let reply = replies.isEmpty ? [] : replies.removeFirst()
            return AsyncThrowingStream { continuation in
                for piece in reply { continuation.yield(.delta(piece)) }
                continuation.yield(.finished)
                continuation.finish()
            }
        }
    }
}

private func collect(_ stream: LazyStream<ChunkedEvent>) async throws -> [ChunkedEvent] {
    var events: [ChunkedEvent] = []
    for try await event in stream { events.append(event) }
    return events
}

/// Collects until the stream throws, and returns what came before.
private func collectUntilFailure(_ stream: LazyStream<ChunkedEvent>) async -> (events: [ChunkedEvent], failed: Bool) {
    var events: [ChunkedEvent] = []
    do {
        for try await event in stream { events.append(event) }
    } catch {
        return (events, true)
    }
    return (events, false)
}

private func finished(_ events: [ChunkedEvent]) -> ChunkedResult? {
    guard case .finished(let result) = events.last else { return nil }
    return result
}

private func blocks(_ texts: [String], audience: String? = nil) -> [String] {
    let quoted = texts.map { "\"\($0)\"" }.joined(separator: ", ")
    guard let audience else { return ["{\"blocks\": [\(quoted)]}"] }
    return ["{\"detected_audience\": \"\(audience)\", \"audience_evidence\": \"Dear students\", \"blocks\": [\(quoted)]}"]
}

private func corrected(_ texts: [String], _ errors: String = "[]") -> [String] {
    let quoted = texts.map { "\"\($0)\"" }.joined(separator: ", ")
    return ["{\"corrected_blocks\": [\(quoted)], \"errors\": \(errors)}"]
}

private func error(_ original: String, _ fixed: String) -> String {
    "[{\"original\": \"\(original)\", \"corrected\": \"\(fixed)\", \"category\": \"spelling\", "
        + "\"explanation\": \"typo\", \"severity\": \"error\"}]"
}

private let german = LanguageConfig.swissGerman.code
private let english = LanguageConfig.english.code
private let inferring = AudienceRequest.infer(profiles: AudienceProfile.shippedDefaults, fallback: .colleagues)
private let toGerman = Direction(source: english, target: german)

@Suite("Chunked run: one action over a scratchpad text, chunk by chunk (#84)", .timeLimit(.minutes(1)))
struct ChunkedRunTests {

    private func runner(_ chat: ScriptedChat) -> ChunkedRun {
        ChunkedRun(configuration: .default, chat: chat)
    }

    /// Two paragraphs that cannot share a chunk.
    private let plan = ChunkPlan("Dear students, hello\n\nSee you soon", limit: 20)

    @Test("one chunk behaves like the popup's single request")
    func single() async throws {
        let chat = ScriptedChat([blocks(["Hallo"])])
        let events = try await collect(runner(chat).run(
            ChunkPlan("Hello"), task: .translate(toGerman, .fixed(.colleagues))))
        #expect(events.first == .chunkStarted(index: 0, count: 1))
        let result = try #require(finished(events))
        #expect(result.text == "Hallo")
        #expect(result.source == "Hello")
        #expect(chat.prompts.count == 1)
    }

    @Test("chunks run in order, and the results are joined at the kept separators")
    func joined() async throws {
        let chat = ScriptedChat([blocks(["Hallo"], audience: "students"), blocks(["Bis bald"])])
        let events = try await collect(runner(chat).run(plan, task: .translate(toGerman, inferring)))
        let starts = events.filter { event in
            guard case .chunkStarted = event else { return false }
            return true
        }
        #expect(starts == [.chunkStarted(index: 0, count: 2), .chunkStarted(index: 1, count: 2)])
        #expect(try #require(finished(events)).text == "Hallo\n\nBis bald")
    }

    @Test("the audience is inferred on the first chunk and fixed for the rest")
    func audienceOnce() async throws {
        let chat = ScriptedChat([blocks(["Hallo"], audience: "students"), blocks(["Bis bald"])])
        let events = try await collect(runner(chat).run(plan, task: .translate(toGerman, inferring)))
        let audiences = events.filter { event in
            guard case .audience = event else { return false }
            return true
        }
        #expect(audiences == [.audience(.students, inferred: true)])
        #expect(chat.prompts[0].contains("audience_evidence"))
        #expect(!chat.prompts[1].contains("audience_evidence"))
        let translation = try #require(finished(events)?.translation)
        #expect(translation.audience == .students)
        #expect(translation.audienceInferred)
        #expect(translation.text == UserText("Hallo\n\nBis bald"))
    }

    @Test("a later chunk of a translation writes for the first chunk's audience")
    func following() throws {
        let first = TranslationResult(
            text: UserText("Hallo"), direction: toGerman, warnings: [], audience: .students,
            audienceInferred: true)
        let run = ChunkedRun(configuration: .default, chat: ScriptedChat([]))
        #expect(run.following(.translate(toGerman, inferring), [.translation(first)])
            == .translate(toGerman, .fixed(.students)))
        #expect(run.following(.translate(toGerman, inferring), []) == .translate(toGerman, inferring))
        #expect(run.following(.repitch(german, .informal), [.translation(first)]) == .repitch(german, .informal))
    }

    @Test("a failed chunk keeps the chunks before it, and the stream throws")
    func failure() async throws {
        let chat = ScriptedChat([blocks(["Hallo"]), ["  "]])
        let (events, failed) = await collectUntilFailure(
            runner(chat).run(plan, task: .translate(toGerman, .fixed(.colleagues))))
        #expect(failed)
        let done = events.compactMap { event -> Int? in
            guard case .chunkFinished(let index, _) = event else { return nil }
            return index
        }
        #expect(done == [0])
        #expect(finished(events) == nil)
    }

    @Test("continuing sends only the chunks after the completed ones")
    func resume() async throws {
        let first = TranslationResult(
            text: UserText("Hallo"), direction: toGerman, warnings: [], audience: .students,
            audienceInferred: true)
        let chat = ScriptedChat([blocks(["Bis bald"])])
        let events = try await collect(runner(chat).run(
            plan, task: .translate(toGerman, inferring), completed: [.translation(first)]))
        #expect(chat.prompts.count == 1)
        #expect(chat.prompts[0].contains("See you soon"))
        #expect(!chat.prompts[0].contains("audience_evidence"))
        #expect(events.first == .chunkStarted(index: 1, count: 2))
        let result = try #require(finished(events))
        #expect(result.text == "Hallo\n\nBis bald")
        #expect(result.translation?.audience == .students)
    }

    @Test("nothing is sent when every chunk is already done")
    func alreadyDone() async throws {
        let only = TranslationResult(
            text: UserText("Hallo"), direction: toGerman, warnings: [], audience: .colleagues,
            audienceInferred: false)
        let chat = ScriptedChat([])
        let events = try await collect(runner(chat).run(
            ChunkPlan("Hello"), task: .translate(toGerman, .fixed(.colleagues)), completed: [.translation(only)]))
        #expect(chat.prompts.isEmpty)
        #expect(finished(events)?.text == "Hallo")
    }

    @Test("Re-pitch runs per chunk in the text's language")
    func repitch() async throws {
        let chat = ScriptedChat([blocks(["Hoi"]), blocks(["Tschau"])])
        let plan = ChunkPlan("Grüezi mitenand\n\nAuf Wiedersehen", limit: 16)
        let events = try await collect(runner(chat).run(plan, task: .repitch(german, .informal)))
        let audiences = events.filter { event in
            guard case .audience = event else { return false }
            return true
        }
        #expect(audiences.isEmpty)
        let translation = try #require(finished(events)?.translation)
        #expect(translation.text == UserText("Hoi\n\nTschau"))
        #expect(translation.direction == Direction(source: german, target: german))
    }

    @Test("Correct merges errors in text order, and diffs the whole text")
    func correct() async throws {
        let chat = ScriptedChat([
            corrected(["Ich habe Zeit."], error("Ich hab", "Ich habe")),
            corrected(["Bis morgen."], error("Biss", "Bis")),
        ])
        let plan = ChunkPlan("Ich hab Zeit.\n\nBiss morgen.", limit: 14)
        let events = try await collect(runner(chat).run(plan, task: .correct(german, .colleagues)))
        let correction = try #require(finished(events)?.correction)
        #expect(correction.errors.map(\.original) == ["Ich hab", "Biss"])
        #expect(correction.original == UserText("Ich hab Zeit.\n\nBiss morgen."))
        #expect(correction.corrected == UserText("Ich habe Zeit.\n\nBis morgen."))
        #expect(!correction.hasNoErrors)
        #expect(correction.diff.contains(.removed("Biss")))
        #expect(correction.diff.contains(.added("Bis")))
    }

    @Test("Correct has no errors only when no chunk had any")
    func noErrors() async throws {
        let chat = ScriptedChat([corrected(["Ich habe Zeit."]), corrected(["Bis morgen."])])
        let plan = ChunkPlan("Ich habe Zeit.\n\nBis morgen.", limit: 14)
        let events = try await collect(runner(chat).run(plan, task: .correct(german, .colleagues)))
        #expect(try #require(finished(events)?.correction).hasNoErrors)
    }

    @Test("Explain runs on the whole text as one chunk")
    func explain() async throws {
        let chat = ScriptedChat([["{\"summary\": \"A greeting.\", \"notes\": []}"]])
        let text = "Grüezi mitenand\n\nAuf Wiedersehen"
        let events = try await collect(runner(chat).run(.whole(text), task: .explain(german)))
        let result = try #require(finished(events))
        #expect(result.explanation?.summary == "A greeting.")
        #expect(result.text == "A greeting.")
        #expect(chat.prompts.count == 1)
        #expect(chat.prompts[0].contains("Auf Wiedersehen"))
    }

    @Test("a result of another kind has no translation, correction or explanation")
    func kinds() {
        let explanation = ExplanationResult(summary: "S", notes: [], warnings: [])
        let result = ChunkedResult(
            task: .explain(german), source: "x", text: "S", outputs: [.explanation(explanation)],
            warnings: [])
        #expect(result.translation == nil)
        #expect(result.correction == nil)
        let none = ChunkedResult(task: .correct(german, .colleagues), source: "", text: "", outputs: [], warnings: [])
        #expect(none.correction == nil)
        #expect(none.explanation == nil)
    }

    @Test("warnings name their part only when there are several")
    func warnings() {
        func output(_ warnings: [String]) -> ChunkOutput {
            .translation(TranslationResult(
                text: UserText("t"), direction: toGerman, warnings: warnings, audience: .colleagues,
                audienceInferred: false))
        }
        #expect(ChunkedRun.warnings([output(["w"])]) == ["w"])
        #expect(ChunkedRun.warnings([output([]), output(["w", "v"])])
            == ["Part 2 of 2: w", "Part 2 of 2: v"])
    }

    @Test("each run is one History record, from the Scratchpad, with the whole text")
    func record() async throws {
        let chat = ScriptedChat([blocks(["Hallo"], audience: "students"), blocks(["Bis bald"])])
        let events = try await collect(runner(chat).run(plan, task: .translate(toGerman, inferring)))
        let date = Date(timeIntervalSince1970: 1)
        let record = try #require(finished(events)?.record(model: "m", myLanguage: english, date: date))
        #expect(record.action == .translate)
        #expect(record.sourceAppName == "Scratchpad")
        #expect(record.sourceBundleID == nil)
        #expect(record.source == UserText("Dear students, hello\n\nSee you soon"))
        #expect(record.result == UserText("Hallo\n\nBis bald"))
        #expect(record.profileID == AudienceProfile.students.id)
        #expect(record.targetLanguage == german)
        #expect(record.date == date)
    }

    @Test("records for Re-pitch, Correct and Explain")
    func records() {
        let translation = TranslationResult(
            text: UserText("Hoi"), direction: Direction(source: german, target: german), warnings: [],
            audience: .informal, audienceInferred: false)
        let repitch = ChunkedResult(
            task: .repitch(german, .informal), source: "Grüezi", text: "Hoi",
            outputs: [.translation(translation)], warnings: [])
        #expect(repitch.record(model: "m", myLanguage: english, date: Date())?.action == .repitch)

        let correction = CorrectionResult(
            original: UserText("a"), corrected: UserText("b"), errors: [], suggestions: [], diff: [],
            warnings: [], hasNoErrors: false)
        let correct = ChunkedResult(
            task: .correct(german, .colleagues), source: "a", text: "b",
            outputs: [.correction(correction)], warnings: [])
        let corrected = correct.record(model: "m", myLanguage: english, date: Date())
        #expect(corrected?.action == .correct)
        #expect(corrected?.profileID == AudienceProfile.colleagues.id)
        #expect(corrected?.result == UserText("b"))

        let explanation = ExplanationResult(summary: "S", notes: [], warnings: [])
        let explain = ChunkedResult(
            task: .explain(german), source: "a", text: "S", outputs: [.explanation(explanation)],
            warnings: [])
        let explained = explain.record(model: "m", myLanguage: english, date: Date())
        #expect(explained?.action == .explain)
        #expect(explained?.targetLanguage == english)

        let mismatched = ChunkedResult(
            task: .explain(german), source: "a", text: "S", outputs: [.correction(correction)],
            warnings: [])
        #expect(mismatched.record(model: "m", myLanguage: english, date: Date()) == nil)
    }

    @Test("the task names its action")
    func action() {
        #expect(ChunkTask.translate(toGerman, inferring).action == .translate)
        #expect(ChunkTask.repitch(german, .informal).action == .repitch)
        #expect(ChunkTask.correct(german, .informal).action == .correct)
        #expect(ChunkTask.explain(german).action == .explain)
    }
}
