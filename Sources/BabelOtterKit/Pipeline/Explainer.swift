import Foundation

public enum ExplanationEvent: Sendable, Equatable {
    case started
    /// Another piece of the reply arrived. Carries nothing; the notes stream
    /// after the summary with no visible change, so this is what tells an
    /// idle timeout the reply is live.
    case progress
    /// The summary so far, post-processed, terms restored. Never the result.
    case summary(String)
    case finished(ExplanationResult)
}

public struct ExplanationResult: Sendable, Equatable {
    public let summary: String
    public let notes: [ExplainNote]
    public let warnings: [String]

    /// What Copy writes: the summary, then one line per note.
    public var copyText: String {
        if notes.isEmpty { return summary }
        let lines = notes.map { "- \"" + $0.phrase + "\": " + $0.explanationEn }
        return summary + "\n\n" + lines.joined(separator: "\n")
    }
}

public enum ExplanationFailure: Error, Equatable {
    /// Detection has a guess, and it is not German. Nothing was sent.
    case notGerman
    /// The reply did not parse, or had no summary. Never shown as an explanation.
    case unreadableReply
    case emptyResponse
}

/// German text in, an English explanation out (`FR-EXP-01`, #65).
///
/// Shaped like `Corrector`, with two differences: the text goes to the model
/// as one block, since a summary has no paragraph layout to keep, and only
/// placeholder debris warns, since an explanation need not repeat a
/// protected term.
public struct Explainer: Sendable {

    /// Explain reads German (spec 2026-10-15). The base subtag, so any
    /// configured German locale qualifies.
    static let german = LanguageCode("de")
    static let english = LanguageCode("en")

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

    /// Lazy for the same reason `OllamaClient.chat` is: building the value
    /// must not transmit the user's text (NFR-P1).
    public func explain(_ text: UserText, styleNote: String? = nil) -> LazyStream<ExplanationEvent> {
        LazyStream { [self] in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        try await run(text, styleNote: styleNote) { continuation.yield($0) }
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

    private struct Context {
        let german: LanguageConfig
        let english: LanguageConfig
        let styleNote: String?
        let model: String
        let masked: ProtectedText
        let processor: PostProcessor
    }

    private func run(
        _ text: UserText, styleNote: String?, emit: (ExplanationEvent) -> Void
    ) async throws {
        try gate(text)
        let english = language(Self.english, or: .english)
        let context = Context(
            german: configuration.germanLanguage, english: english,
            styleNote: styleNote,
            model: configuration.model(for: .explain),
            masked: TokenProtector.mask(text.value, terms: configuration.doNotTranslate),
            processor: PostProcessor(target: english))
        emit(.started)
        let raw = try await generate(context, emit)
        emit(.finished(try result(raw, context)))
    }

    /// The configured language with this base subtag, so its display name
    /// and locale rules apply; the shipped default otherwise.
    private func language(_ code: LanguageCode, or fallback: LanguageConfig) -> LanguageConfig {
        configuration.enabledLanguages.first { $0.code.baseSubtag == code } ?? fallback
    }

    /// Refuses only a confident guess that is not German. Anything less goes
    /// through: unlike Correct, Explain is for German the user does not
    /// follow, and dialect or German mixed with English is exactly what
    /// the recognizer is unsure of (spec 2026-10-15, final review).
    private func gate(_ text: UserText) throws {
        guard case .confident(let guess, _) = detector.detect(text.value) else { return }
        guard guess.baseSubtag == Self.german else { throw ExplanationFailure.notGerman }
    }

    private func generate(
        _ context: Context, _ emit: (ExplanationEvent) -> Void
    ) async throws -> String {
        let prompt = PromptBuilder().build(PromptRequest(
            action: .explain, source: context.german, target: context.english,
            profile: .colleagues, doNotTranslate: configuration.doNotTranslate,
            styleNote: context.styleNote, blocks: [context.masked.text]))
        var shown = ""
        let raw = try await ReplyStream.collect(
            chat: chat, model: context.model, prompt: prompt, key: "notes",
            onRaw: { raw in
                guard let partial = PartialField.prefix(named: "summary_en", in: raw) else { return }
                if partial == shown { return }
                shown = partial
                emit(.summary(context.processor.finish(partial, protected: context.masked).text))
            },
            onDelta: { emit(.progress) },
            onPartial: { _ in })
        if isBlank(raw) { throw ExplanationFailure.emptyResponse }
        return raw
    }

    private func result(_ raw: String, _ context: Context) throws -> ExplanationResult {
        let response: ExplainResponse
        do {
            response = try ResponseParser.parseExplain(raw)
        } catch {
            throw ExplanationFailure.unreadableReply
        }
        let summary = context.processor.finish(response.summaryEn, protected: context.masked)
        if isBlank(summary.text) { throw ExplanationFailure.unreadableReply }
        var problems = summary.problems
        var notes: [ExplainNote] = []
        for item in response.notes {
            // The phrase quotes the user's German: terms restored, no rules.
            let phrase = TokenProtector.restore(item.phrase, from: context.masked)
            let explanation = context.processor.finish(item.explanationEn, protected: context.masked)
            if isBlank(phrase.text) { continue }
            if isBlank(explanation.text) { continue }
            problems += phrase.problems
            problems += explanation.problems
            notes.append(ExplainNote(phrase: phrase.text, explanationEn: explanation.text))
        }
        return ExplanationResult(summary: summary.text, notes: notes, warnings: warnings(problems))
    }

    private func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A protected term missing from an explanation is normal: it need not
    /// repeat the term. Only a placeholder the model left behind is shown.
    private func warnings(_ problems: [ProtectionProblem]) -> [String] {
        for problem in problems {
            if case .sentinelDebris = problem {
                return ["The model left a placeholder behind; check the text before using it."]
            }
        }
        return []
    }
}
