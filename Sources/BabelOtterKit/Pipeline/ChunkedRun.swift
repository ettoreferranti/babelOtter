import Foundation

/// What a scratchpad run does, settled before any chunk is sent (#84): the
/// language and the direction are decided once, on the whole text.
public enum ChunkTask: Sendable, Equatable {
    case translate(Direction, AudienceRequest)
    case repitch(LanguageCode, AudienceProfile)
    case correct(LanguageCode, AudienceProfile)
    case explain(LanguageCode)

    public var action: Action {
        switch self {
        case .translate: return .translate
        case .repitch: return .repitch
        case .correct: return .correct
        case .explain: return .explain
        }
    }
}

/// One chunk's finished result, as its pipeline produced it.
public enum ChunkOutput: Sendable, Equatable {
    case translation(TranslationResult)
    case correction(CorrectionResult)
    case explanation(ExplanationResult)

    /// What the chunk contributes to the joined result.
    public var text: String {
        switch self {
        case .translation(let result): return result.text.value
        case .correction(let result): return result.corrected.value
        case .explanation(let result): return result.copyText
        }
    }
}

public enum ChunkedEvent: Sendable, Equatable {
    /// `index` counts from zero.
    case chunkStarted(index: Int, count: Int)
    /// A piece of the model's reply arrived; for the idle timeout.
    case progress
    /// Translate's audience, from the first chunk only: the rest write for it.
    /// Never for Re-pitch, whose audience is the one picked.
    case audience(AudienceProfile, inferred: Bool)
    /// The current chunk's text so far. Never a result.
    case preview(String)
    case chunkFinished(index: Int, ChunkOutput)
    case finished(ChunkedResult)
}

/// Every chunk's result, joined.
public struct ChunkedResult: Sendable, Equatable {
    public let task: ChunkTask
    /// The text as the user wrote it.
    public let source: String
    /// What Copy writes.
    public let text: String
    public let outputs: [ChunkOutput]
    /// Each chunk's warnings, marked with its part when there are several.
    public let warnings: [String]

    /// Translate and Re-pitch: the joined result, with the first chunk's
    /// audience.
    public var translation: TranslationResult? {
        guard case .translation(let first) = outputs.first else { return nil }
        return TranslationResult(
            text: UserText(text), direction: first.direction, warnings: warnings,
            audience: first.audience, audienceInferred: first.audienceInferred)
    }

    /// Correct: the errors and suggestions of all chunks in text order, the
    /// diff over the whole text, and "no errors" only when no chunk had any.
    public var correction: CorrectionResult? {
        var errors: [CorrectionError] = []
        var suggestions: [CorrectionError] = []
        var hasNoErrors = true
        for output in outputs {
            guard case .correction(let result) = output else { return nil }
            errors += result.errors
            suggestions += result.suggestions
            hasNoErrors = hasNoErrors && result.hasNoErrors
        }
        guard !outputs.isEmpty else { return nil }
        return CorrectionResult(
            original: UserText(source), corrected: UserText(text), errors: errors,
            suggestions: suggestions, diff: WordDiff.diff(source, text), warnings: warnings,
            hasNoErrors: hasNoErrors)
    }

    /// Explain: never chunked, so the one result.
    public var explanation: ExplanationResult? {
        guard case .explanation(let result) = outputs.first else { return nil }
        return result
    }

    /// The History record of this run, from the scratchpad (#84).
    public func record(model: String, myLanguage: LanguageCode, date: Date) -> HistoryRecord? {
        let application = SourceApplication.scratchpad
        let source = UserText(self.source)
        switch task {
        case .translate:
            guard let translation else { return nil }
            return HistoryRecord(
                translation: translation, source: source, model: model,
                application: application, date: date)
        case .repitch:
            guard let translation else { return nil }
            return HistoryRecord(
                repitch: translation, source: source, model: model,
                application: application, date: date)
        case .correct(let language, let profile):
            guard let correction else { return nil }
            return HistoryRecord(
                correction: correction, language: language, profileID: profile.id,
                model: model, application: application, date: date)
        case .explain(let language):
            guard let explanation else { return nil }
            return HistoryRecord(
                explanation: explanation, source: source, language: language,
                explainedIn: myLanguage, model: model, application: application, date: date)
        }
    }
}

extension SourceApplication {
    /// What History shows as the app for a scratchpad result (#84). No
    /// bundle ID, and the process is never looked at.
    public static let scratchpad = SourceApplication(
        processIdentifier: 0, bundleIdentifier: nil, name: "Scratchpad")
}

/// Runs one task over a `ChunkPlan`'s chunks, one after another, through
/// the popup's own pipelines (#84).
///
/// A run that stopped -- cancelled, timed out or failed -- continues from
/// where it stopped: the caller passes back the outputs it already has, and
/// only the chunks after them are sent.
public struct ChunkedRun: Sendable {

    private let configuration: Configuration
    private let translator: Translator
    private let corrector: Corrector
    private let explainer: Explainer

    public init(
        configuration: Configuration, chat: any ChatStreaming,
        recognizer: (any LanguageRecognizing)? = nil
    ) {
        self.configuration = configuration
        self.translator = Translator(configuration: configuration, chat: chat, recognizer: recognizer)
        self.corrector = Corrector(configuration: configuration, chat: chat, recognizer: recognizer)
        self.explainer = Explainer(configuration: configuration, chat: chat, recognizer: recognizer)
    }

    /// Lazy, like every pipeline: building the value sends nothing.
    /// `completed` are the outputs of the first chunks from an earlier,
    /// stopped run of the same task on the same plan.
    public func run(
        _ plan: ChunkPlan, task: ChunkTask, styleNote: String? = nil,
        completed: [ChunkOutput] = []
    ) -> LazyStream<ChunkedEvent> {
        LazyStream { [self] in
            AsyncThrowingStream { continuation in
                let job = Task {
                    do {
                        try await runAll(plan, task, styleNote, completed) { continuation.yield($0) }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in job.cancel() }
            }
        }
    }

    private func runAll(
        _ plan: ChunkPlan, _ task: ChunkTask, _ styleNote: String?, _ completed: [ChunkOutput],
        _ emit: (ChunkedEvent) -> Void
    ) async throws {
        var outputs = Array(completed.prefix(plan.chunks.count))
        var index = outputs.count
        while index < plan.chunks.count {
            try Task.checkCancellation()
            emit(.chunkStarted(index: index, count: plan.chunks.count))
            let output = try await runChunk(
                plan.chunks[index], index: index, task: following(task, outputs), styleNote, emit)
            outputs.append(output)
            emit(.chunkFinished(index: index, output))
            index += 1
        }
        emit(.finished(ChunkedResult(
            task: task, source: plan.join(plan.chunks), text: plan.join(outputs.map(\.text)),
            outputs: outputs, warnings: Self.warnings(outputs))))
    }

    /// Translate infers the audience on the first chunk only; every later
    /// chunk writes for the one it chose, so the text keeps one register.
    func following(_ task: ChunkTask, _ outputs: [ChunkOutput]) -> ChunkTask {
        guard case .translate(let direction, _) = task else { return task }
        guard case .translation(let first) = outputs.first else { return task }
        return .translate(direction, .fixed(first.audience))
    }

    private func runChunk(
        _ chunk: String, index: Int, task: ChunkTask, _ styleNote: String?,
        _ emit: (ChunkedEvent) -> Void
    ) async throws -> ChunkOutput {
        let text = UserText(chunk)
        switch task {
        case .translate(let direction, let audience):
            let stream = translator.translate(text, direction: direction, audience: audience, styleNote: styleNote)
            return .translation(try await translation(stream, reportsAudience: index == 0, emit))
        case .repitch(let language, let profile):
            // Re-pitch's audience is the one picked: nothing to report.
            let stream = translator.repitch(text, language: language, audience: profile, styleNote: styleNote)
            return .translation(try await translation(stream, reportsAudience: false, emit))
        case .correct(let language, let profile):
            let stream = corrector.correct(text, in: language, profile: profile, styleNote: styleNote)
            return .correction(try await correction(stream, emit))
        case .explain(let language):
            return .explanation(try await explanation(explainer.explain(text, in: language, styleNote: styleNote), emit))
        }
    }

    private func translation(
        _ stream: LazyStream<TranslationEvent>, reportsAudience: Bool, _ emit: (ChunkedEvent) -> Void
    ) async throws -> TranslationResult {
        for try await event in stream {
            switch event {
            case .started:
                break
            case .audience(let profile, let inferred):
                if reportsAudience { emit(.audience(profile, inferred: inferred)) }
            case .progress:
                emit(.progress)
            case .preview(let partial):
                emit(.preview(partial.value))
            case .finished(let result):
                return result
            }
        }
        throw CancellationError()
    }

    private func correction(
        _ stream: LazyStream<CorrectionEvent>, _ emit: (ChunkedEvent) -> Void
    ) async throws -> CorrectionResult {
        for try await event in stream {
            switch event {
            case .started:
                break
            case .progress:
                emit(.progress)
            case .preview(let partial):
                emit(.preview(partial.value))
            case .finished(let result):
                return result
            }
        }
        throw CancellationError()
    }

    private func explanation(
        _ stream: LazyStream<ExplanationEvent>, _ emit: (ChunkedEvent) -> Void
    ) async throws -> ExplanationResult {
        for try await event in stream {
            switch event {
            case .started:
                break
            case .progress:
                emit(.progress)
            case .summary(let partial):
                emit(.preview(partial))
            case .finished(let result):
                return result
            }
        }
        throw CancellationError()
    }

    /// One list; with several chunks each warning names its part.
    static func warnings(_ outputs: [ChunkOutput]) -> [String] {
        var all: [String] = []
        for index in outputs.indices {
            for warning in warnings(of: outputs[index]) {
                if outputs.count > 1 {
                    all.append("Part \(index + 1) of \(outputs.count): \(warning)")
                } else {
                    all.append(warning)
                }
            }
        }
        return all
    }

    private static func warnings(of output: ChunkOutput) -> [String] {
        switch output {
        case .translation(let result): return result.warnings
        case .correction(let result): return result.warnings
        case .explanation(let result): return result.warnings
        }
    }
}
