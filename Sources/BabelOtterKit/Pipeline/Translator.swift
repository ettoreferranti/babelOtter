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
    /// The audience this translation writes for, once known: as soon as the
    /// model's `detected_audience` has arrived when inferring, at once when
    /// fixed. Exactly once per translation, always before `finished` (#52).
    case audience(AudienceProfile, inferred: Bool)
    /// The model sent another piece of its reply. Carries nothing; it exists
    /// so an idle timeout can tell a slow but live reply from a stalled one,
    /// even while the preview is not changing.
    case progress
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
    /// The audience the text was written for, and whether the model chose it.
    public let audience: AudienceProfile
    public let audienceInferred: Bool
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

    /// The enabled language a text is written in (#66): Re-pitch keeps it.
    /// Not `TargetLanguageResolver`, which calls a text ambiguous whenever
    /// there is more than one language to translate into.
    public func language(for text: UserText) -> Result<LanguageCode, TranslationError> {
        guard case .confident(let detected, _) = detector.detect(text.value) else {
            return .failure(.directionUnknown(candidates: enabledCodes))
        }
        for language in configuration.enabledLanguages {
            if language.code == detected { return .success(language.code) }
            if language.code.baseSubtag == detected.baseSubtag { return .success(language.code) }
        }
        return .failure(.languageNotConfigured(detected))
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
        translate(text, direction: direction, audience: .fixed(profile), styleNote: styleNote)
    }

    /// `.infer` asks the model to choose the audience from the text (#52);
    /// the choice is reported as `.audience` and fixed for the retry.
    public func translate(
        _ text: UserText, direction: Direction, audience: AudienceRequest,
        styleNote: String? = nil
    ) -> LazyStream<TranslationEvent> {
        stream(text, direction: direction, audience: audience, styleNote: styleNote, action: .translate)
    }

    /// The same text in the same language, for `audience` (#66). Always a
    /// fixed audience; no glossary, which is for translating between two
    /// languages; facts of the original that the result lost are warnings.
    public func repitch(
        _ text: UserText, language: LanguageCode, audience: AudienceProfile,
        styleNote: String? = nil
    ) -> LazyStream<TranslationEvent> {
        stream(
            text, direction: Direction(source: language, target: language),
            audience: .fixed(audience), styleNote: styleNote, action: .repitch)
    }

    private func stream(
        _ text: UserText, direction: Direction, audience: AudienceRequest,
        styleNote: String?, action: Action
    ) -> LazyStream<TranslationEvent> {
        LazyStream { [self] in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        try await run(
                            text, direction: direction, audience: audience,
                            styleNote: styleNote, action: action
                        ) {
                            continuation.yield(checked($0, action: action, original: text.value))
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

    /// Re-pitch's finished result gains a warning per fact it lost.
    private func checked(
        _ event: TranslationEvent, action: Action, original: String
    ) -> TranslationEvent {
        guard action == .repitch else { return event }
        guard case .finished(let result) = event else { return event }
        let lost = FactCheck.missing(from: original, in: result.text.value).map {
            "\"" + $0 + "\" from the original is not in the re-pitch."
        }
        return .finished(TranslationResult(
            text: result.text, direction: result.direction, warnings: result.warnings + lost,
            audience: result.audience, audienceInferred: result.audienceInferred))
    }

    // MARK: - The pipeline

    private var enabledCodes: [LanguageCode] { configuration.enabledLanguages.map(\.code) }

    /// The glossary maps terms between two languages; Re-pitch stays in one.
    private func glossary(for action: Action, _ direction: Direction) -> [GlossaryEntry] {
        if action == .repitch { return [] }
        return configuration.glossary.entries(
            for: LanguagePair(source: direction.source, target: direction.target))
    }

    /// The audience one translation settled on, so it is reported once and
    /// the retry and the result use the same one.
    private final class AudienceReport: @unchecked Sendable {
        var profile: AudienceProfile?
        var inferred = false
    }

    private struct Context {
        let action: Action
        let source: LanguageConfig
        let target: LanguageConfig
        var audience: AudienceRequest
        let report: AudienceReport
        /// The selection as the user wrote it, where a quoted sign of the
        /// reader must occur.
        let sourceText: String
        let styleNote: String?
        let glossary: [GlossaryEntry]
        let terms: [String]
        let model: String
        let processor: PostProcessor

        /// The audience the prompt writes for: the reported one once known,
        /// else the fixed one or the fallback.
        var writingFor: AudienceProfile {
            if let reported = report.profile { return reported }
            switch audience {
            case .fixed(let profile):
                return profile
            case .infer(_, let fallback):
                return fallback
            }
        }

        /// The audiences to choose from, or none for a fixed audience.
        var choices: [AudienceProfile] {
            guard case .infer(let profiles, _) = audience else { return [] }
            return profiles
        }
    }

    private func run(
        _ text: UserText, direction: Direction, audience: AudienceRequest, styleNote: String?,
        action: Action, emit: (TranslationEvent) -> Void
    ) async throws {
        guard let source = configuration.language(for: direction.source) else {
            throw TranslationError.languageNotConfigured(direction.source)
        }
        guard let target = configuration.language(for: direction.target) else {
            throw TranslationError.languageNotConfigured(direction.target)
        }
        let context = Context(
            action: action,
            source: source, target: target, audience: audience, report: AudienceReport(),
            sourceText: text.value,
            styleNote: styleNote,
            glossary: glossary(for: action, direction),
            terms: configuration.doNotTranslate,
            model: configuration.models[action] ?? Configuration.defaultModel,
            processor: PostProcessor(target: target))
        emit(.started(direction))
        if case .fixed = audience { settle(nil, nil, context, emit) }

        let extracted = StructureExtractor.extract(text.value)
        let masked = extracted.blocks.map { TokenProtector.mask($0, terms: context.terms) }
        let raw = try await generate(masked, context, emit)

        guard case .decoded(let response) = ResponseParser.parseTranslate(raw) else {
            settle(nil, nil, context, emit)
            return emit(.finished(unparsed(raw, masked.first, direction, context)))
        }
        settle(response.detectedAudience, response.audienceEvidence, context, emit)
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
                warnings: warnings(finished.flatMap(\.problems)),
                audience: context.writingFor, audienceInferred: context.report.inferred)))
        case .retryWholeText:
            var fixed = context
            fixed.audience = .fixed(context.writingFor)
            try await retryWholeText(text, direction, fixed, emit)
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
            warnings: warnings(finished.problems),
            audience: context.writingFor, audienceInferred: context.report.inferred)))
    }

    private func generate(
        _ blocks: [ProtectedText], _ context: Context, _ emit: (TranslationEvent) -> Void
    ) async throws -> String {
        let prompt = PromptBuilder().build(PromptRequest(
            action: context.action, source: context.source, target: context.target,
            profile: context.writingFor, inferAudienceFrom: context.choices,
            glossary: context.glossary,
            doNotTranslate: context.terms, styleNote: context.styleNote,
            blocks: blocks.map(\.text)))
        let raw = try await ReplyStream.collect(
            chat: chat, model: context.model, prompt: prompt, key: "blocks",
            onRaw: { reply in
                guard !context.choices.isEmpty else { return }
                guard let detected = PartialField.string(named: "detected_audience", in: reply) else { return }
                guard let evidence = PartialField.string(named: "audience_evidence", in: reply) else { return }
                settle(detected, evidence, context, emit)
            },
            onDelta: { emit(.progress) },
            onPartial: { emit(.preview(UserText(preview($0, blocks, context)))) })
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
            return TranslationResult(
                text: UserText(text), direction: direction, warnings: [format],
                audience: context.writingFor, audienceInferred: context.report.inferred)
        }
        let finished = context.processor.finish(raw, protected: protected)
        return TranslationResult(
            text: UserText(finished.text), direction: direction,
            warnings: [format] + warnings(finished.problems),
            audience: context.writingFor, audienceInferred: context.report.inferred)
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
            warnings: [reason],
            audience: context.writingFor, audienceInferred: context.report.inferred)
    }

    /// Reports the audience if it has not been yet: when inferring, the
    /// model's answer if it names a configured audience and quotes words the
    /// text really contains, else the fallback; the fixed one otherwise.
    private func settle(
        _ detected: String?, _ evidence: String?, _ context: Context,
        _ emit: (TranslationEvent) -> Void
    ) {
        guard context.report.profile == nil else { return }
        var chosen = context.writingFor
        var inferred = false
        if case .infer(let profiles, _) = context.audience {
            if let matched = AudienceInference.match(detected, in: profiles) {
                if AudienceInference.isEvidence(evidence, in: context.sourceText) {
                    chosen = matched
                    inferred = true
                }
            }
        }
        context.report.profile = chosen
        context.report.inferred = inferred
        emit(.audience(chosen, inferred: inferred))
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
