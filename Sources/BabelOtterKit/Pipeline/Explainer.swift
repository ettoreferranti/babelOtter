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
        let lines = notes.map { "- \"" + $0.phrase + "\": " + $0.explanation }
        return summary + "\n\n" + lines.joined(separator: "\n")
    }
}

public enum ExplanationFailure: Error, Equatable {
    /// The text is already in my language (#81). Nothing was sent.
    case alreadyMine(LanguageCode)
    /// The text is in a language that is not enabled. Nothing was sent.
    case notEnabled(LanguageCode)
    /// Detection could not tell, and there is more than one candidate: ask
    /// which. Nothing was sent.
    case needsLanguage([LanguageCode])
    /// The reply did not parse, or had no summary. Never shown as an explanation.
    case unreadableReply
    case emptyResponse
}

/// A text in an enabled language in, an explanation in my language out
/// (`FR-EXP-01`, #65, #81).
///
/// Shaped like `Corrector`, with two differences: the text goes to the model
/// as one block, since a summary has no paragraph layout to keep, and only
/// placeholder debris warns, since an explanation need not repeat a
/// protected term.
public struct Explainer: Sendable {

    private let configuration: Configuration
    private let chat: any ChatStreaming
    private let detector: LanguageDetector

    public init(
        configuration: Configuration,
        chat: any ChatStreaming,
        recognizer: (any LanguageRecognizing)? = nil
    ) {
        self.configuration = configuration
        self.chat = chat
        self.detector = LanguageDetector(configuration: configuration, recognizer: recognizer)
    }

    /// Lazy for the same reason `OllamaClient.chat` is: building the value
    /// must not transmit the user's text (NFR-P1).
    ///
    /// `language` is the text's language when the caller already knows it;
    /// nil resolves it as `language(for:)` does.
    public func explain(
        _ text: UserText, in language: LanguageCode? = nil, styleNote: String? = nil
    ) -> LazyStream<ExplanationEvent> {
        LazyStream { [self] in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        try await run(text, in: language, styleNote: styleNote) { continuation.yield($0) }
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
        let source: LanguageConfig
        let mine: LanguageConfig
        let styleNote: String?
        let model: String
        let masked: ProtectedText
        let processor: PostProcessor
    }

    private func run(
        _ text: UserText, in given: LanguageCode?, styleNote: String?, emit: (ExplanationEvent) -> Void
    ) async throws {
        let source = try textLanguage(text, given: given)
        let mine = configuration.mine
        let context = Context(
            source: source, mine: mine,
            styleNote: styleNote,
            model: configuration.model(for: .explain),
            masked: TokenProtector.mask(text.value, terms: configuration.doNotTranslate),
            processor: PostProcessor(target: mine))
        emit(.started)
        let raw = try await generate(context, emit)
        emit(.finished(try result(raw, context)))
    }

    /// The language this text would be explained from (#81): any enabled
    /// language but mine; see `TextLanguage`.
    public func language(for text: UserText) -> TextLanguageResolution {
        TextLanguage.resolve(detector.detect(text.value), configuration: configuration, excludingMine: true)
    }

    private func textLanguage(_ text: UserText, given: LanguageCode?) throws -> LanguageConfig {
        var code: LanguageCode
        if let given {
            code = given
        } else {
            switch language(for: text) {
            case .known(let known): code = known
            case .mine(let mine): throw ExplanationFailure.alreadyMine(mine)
            case .notEnabled(let other): throw ExplanationFailure.notEnabled(other)
            case .ask(let candidates): throw ExplanationFailure.needsLanguage(candidates)
            }
        }
        guard let language = configuration.language(for: code) else {
            throw ExplanationFailure.notEnabled(code)
        }
        guard language.enabled else { throw ExplanationFailure.notEnabled(code) }
        guard code != configuration.myLanguageCode else { throw ExplanationFailure.alreadyMine(code) }
        return language
    }

    private func generate(
        _ context: Context, _ emit: (ExplanationEvent) -> Void
    ) async throws -> String {
        let prompt = PromptBuilder().build(PromptRequest(
            action: .explain, source: context.source, target: context.mine,
            profile: .colleagues, doNotTranslate: configuration.doNotTranslate,
            styleNote: context.styleNote, blocks: [context.masked.text]))
        var shown = ""
        let raw = try await ReplyStream.collect(
            chat: chat, model: context.model, prompt: prompt, key: "notes",
            onRaw: { raw in
                guard let partial = PartialField.prefix(named: "summary", in: raw) else { return }
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
        let summary = context.processor.finish(response.summary, protected: context.masked)
        if isBlank(summary.text) { throw ExplanationFailure.unreadableReply }
        var problems = summary.problems
        var notes: [ExplainNote] = []
        for item in response.notes {
            // The phrase quotes the user's text: terms restored, no rules.
            let phrase = TokenProtector.restore(item.phrase, from: context.masked)
            let explanation = context.processor.finish(item.explanation, protected: context.masked)
            if isBlank(phrase.text) { continue }
            if isBlank(explanation.text) { continue }
            problems += phrase.problems
            problems += explanation.problems
            notes.append(ExplainNote(phrase: phrase.text, explanation: explanation.text))
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
