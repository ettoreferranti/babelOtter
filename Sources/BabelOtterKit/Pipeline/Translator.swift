import Foundation

/// Which way a translation goes.
public struct Direction: Sendable, Equatable {
    public let source: LanguageCode
    public let target: LanguageCode

    public init(source: LanguageCode, target: LanguageCode) {
        self.source = source
        self.target = target
    }

    public var swapped: Direction { Direction(source: target, target: source) }
}

/// The one thing the translator needs from Ollama, so tests can script it.
public protocol ChatStreaming: Sendable {
    func chat(model: String, messages: [ChatMessage]) -> LazyStream<StreamEvent>
}

extension OllamaClient: ChatStreaming {}

public enum TranslationEvent: Sendable, Equatable {
    case started(Direction)
    /// The translation so far, post-processed. Never the result.
    case preview(UserText)
    case finished(TranslationResult)
}

public struct TranslationResult: Sendable, Equatable {
    public let text: UserText
    public let direction: Direction
    /// Things the user should know before pasting: lost structure, a
    /// protected term that did not come back.
    public let warnings: [String]
}

public enum TranslationError: Error, Equatable {
    /// Detection could not decide; ask, offering these.
    case directionUnknown(candidates: [LanguageCode])
    case languageNotConfigured(LanguageCode)
    case emptyResponse
}

/// Selected text in, translation out: the whole core pipeline behind one call.
///
/// Every step already exists and is proven on its own; this owns only the
/// order and the one retry. `PipelineTests` drives the same order by hand.
public struct Translator: Sendable {

    private let configuration: Configuration
    private let chat: any ChatStreaming
    private let detector: LanguageDetector

    public init(
        configuration: Configuration,
        chat: any ChatStreaming,
        recognizer: any LanguageRecognizing = NaturalLanguageRecognizer()
    ) {
        self.configuration = configuration
        self.chat = chat
        self.detector = LanguageDetector(configuration: configuration, recognizer: recognizer)
    }

    public func direction(for text: UserText) -> Result<Direction, TranslationError> {
        let resolution = TargetLanguageResolver(configuration: configuration)
            .resolve(detector.detect(text.value))
        switch resolution {
        case .resolved(let source, let target):
            return .success(Direction(source: source, target: target))
        case .notEnabled(let code):
            return .failure(.languageNotConfigured(code))
        case .ambiguousPairing(let candidates):
            if candidates.isEmpty {
                return .failure(.directionUnknown(candidates: enabledCodes))
            }
            return .failure(.directionUnknown(candidates: candidates))
        case .needsUserChoice:
            return .failure(.directionUnknown(candidates: enabledCodes))
        }
    }

    /// The direction for a target the user picked: from the first other
    /// enabled language.
    public func direction(into target: LanguageCode) -> Direction? {
        guard configuration.language(for: target) != nil else { return nil }
        guard let source = configuration.enabledLanguages.first(where: { $0.code != target })
        else { return nil }
        return Direction(source: source.code, target: target)
    }

    /// Lazy for the same reason `OllamaClient.chat` is: building the value
    /// must not transmit the user's text (NFR-P1).
    ///
    /// `styleNote` is the user's free-text instruction for this one
    /// invocation ("shorter", "use Sie"). It goes into every prompt the
    /// translation sends, the whole-text retry included.
    public func translate(
        _ text: UserText, direction: Direction, profile: AudienceProfile,
        styleNote: String? = nil
    ) -> LazyStream<TranslationEvent> {
        LazyStream { [self] in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        try await run(
                            text, direction: direction, profile: profile, styleNote: styleNote
                        ) {
                            continuation.yield($0)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }

    // MARK: - The pipeline

    private var enabledCodes: [LanguageCode] { configuration.enabledLanguages.map(\.code) }

    private struct Context {
        let source: LanguageConfig
        let target: LanguageConfig
        let profile: AudienceProfile
        let styleNote: String?
        let glossary: [GlossaryEntry]
        let terms: [String]
        let model: String
        let processor: PostProcessor
    }

    private func run(
        _ text: UserText, direction: Direction, profile: AudienceProfile, styleNote: String?,
        emit: (TranslationEvent) -> Void
    ) async throws {
        guard let source = configuration.language(for: direction.source) else {
            throw TranslationError.languageNotConfigured(direction.source)
        }
        guard let target = configuration.language(for: direction.target) else {
            throw TranslationError.languageNotConfigured(direction.target)
        }
        let context = Context(
            source: source, target: target, profile: profile, styleNote: styleNote,
            glossary: configuration.glossary.entries(
                for: LanguagePair(source: direction.source, target: direction.target)),
            terms: configuration.doNotTranslate,
            model: configuration.models[.translate] ?? Configuration.defaultModel,
            processor: PostProcessor(target: target))
        emit(.started(direction))

        let extracted = StructureExtractor.extract(text.value)
        let masked = extracted.blocks.map { TokenProtector.mask($0, terms: context.terms) }
        let raw = try await generate(masked, context, emit)

        guard case .decoded(let response) = ResponseParser.parseTranslate(raw) else {
            return emit(.finished(unparsed(raw, masked.first, direction, context)))
        }
        let decision = BlockCountPolicy().decide(
            expected: extracted.skeleton.blockCount, received: response.blocks.count, attempt: 0)
        switch decision {
        case .accept:
            let finished = zip(response.blocks, masked).map {
                context.processor.finish($0, protected: $1)
            }
            let output = try StructureExtractor.reapply(
                finished.map(\.text), to: extracted.skeleton)
            emit(.finished(TranslationResult(
                text: UserText(output), direction: direction,
                warnings: warnings(finished.flatMap(\.problems)))))
        case .retryWholeText:
            try await retryWholeText(text, direction, context, emit)
        case .degrade(let reason):
            emit(.finished(joined(response.blocks, masked.first, direction, context, reason)))
        }
    }

    /// The single retry: the whole text as one block, whose line breaks the
    /// model carries through itself.
    private func retryWholeText(
        _ text: UserText, _ direction: Direction, _ context: Context,
        _ emit: (TranslationEvent) -> Void
    ) async throws {
        let whole = TokenProtector.mask(text.value, terms: context.terms)
        let raw = try await generate([whole], context, emit)
        guard case .decoded(let response) = ResponseParser.parseTranslate(raw) else {
            return emit(.finished(unparsed(raw, whole, direction, context)))
        }
        let decision = BlockCountPolicy().decide(
            expected: 1, received: response.blocks.count, attempt: 1)
        guard decision == .accept else {
            var reason = "The model did not keep the text's structure."
            if case .degrade(let detail) = decision { reason = detail }
            return emit(.finished(joined(response.blocks, whole, direction, context, reason)))
        }
        let finished = context.processor.finish(response.blocks[0], protected: whole)
        emit(.finished(TranslationResult(
            text: UserText(finished.text), direction: direction,
            warnings: warnings(finished.problems))))
    }

    private func generate(
        _ blocks: [ProtectedText], _ context: Context, _ emit: (TranslationEvent) -> Void
    ) async throws -> String {
        let prompt = PromptBuilder().build(PromptRequest(
            action: .translate, source: context.source, target: context.target,
            profile: context.profile, glossary: context.glossary,
            doNotTranslate: context.terms, styleNote: context.styleNote,
            blocks: blocks.map(\.text)))

        var raw = ""
        var shown: [String] = []
        for try await event in chat.chat(
            model: context.model, messages: [ChatMessage(role: "user", content: prompt)])
        {
            try Task.checkCancellation()
            guard case .delta(let piece) = event else { continue }
            raw += piece
            let partial = PartialTranslateBlocks.extract(from: raw)
            guard !partial.isEmpty, partial != shown else { continue }
            shown = partial
            emit(.preview(UserText(preview(partial, blocks, context))))
        }
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.emptyResponse
        }
        return raw
    }

    private func preview(
        _ partial: [String], _ blocks: [ProtectedText], _ context: Context
    ) -> String {
        partial.enumerated().map { index, block in
            guard index < blocks.count else { return block }
            return context.processor.finish(block, protected: blocks[index]).text
        }.joined(separator: "\n")
    }

    /// A reply that never became valid JSON is still shown, but any protected
    /// term the model echoed back as a bare sentinel must still come back as
    /// itself rather than as the sentinel -- an unparseable reply is exactly
    /// the case where the user most needs to trust what they are looking at.
    ///
    /// `protected` is `nil` only when there was nothing to mask in the first
    /// place (an empty selection produces zero blocks); today's behaviour --
    /// locale rules with no protected spans -- is kept for that case.
    private func unparsed(
        _ raw: String, _ protected: ProtectedText?, _ direction: Direction, _ context: Context
    ) -> TranslationResult {
        let format = "The model's reply was not in the expected format, so it is shown as it came."
        guard let protected else {
            let text = LocaleRuleApplier.apply(context.processor.rules, to: raw, protecting: [])
            return TranslationResult(text: UserText(text), direction: direction, warnings: [format])
        }
        let finished = context.processor.finish(raw, protected: protected)
        return TranslationResult(
            text: UserText(finished.text), direction: direction,
            warnings: [format] + warnings(finished.problems))
    }

    private func joined(
        _ blocks: [String], _ protected: ProtectedText?, _ direction: Direction,
        _ context: Context, _ reason: String
    ) -> TranslationResult {
        let texts = blocks.map { block -> String in
            guard let protected else { return block }
            return context.processor.finish(block, protected: protected).text
        }
        return TranslationResult(
            text: UserText(texts.joined(separator: "\n")), direction: direction,
            warnings: [reason])
    }

    private func warnings(_ problems: [ProtectionProblem]) -> [String] {
        problems.map { problem in
            switch problem {
            case .sentinelMissing(_, let term):
                return "\"\(term)\" may not have been kept as written."
            case .sentinelDebris:
                return "The model left a placeholder behind; check the text before using it."
            }
        }
    }
}
