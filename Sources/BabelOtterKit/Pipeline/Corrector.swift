import Foundation

public enum CorrectionEvent: Sendable, Equatable {
    case started
    /// The model sent another piece of its reply. Carries nothing; the errors
    /// list streams after the corrected text with no preview change for its
    /// whole length, so this is what tells an idle timeout the reply is live.
    case progress
    /// The corrected text so far, post-processed. Never the result.
    case preview(UserText)
    case finished(CorrectionResult)
}

public struct CorrectionResult: Sendable, Equatable {
    public let original: UserText
    /// Errors fixed only: what Replace pastes.
    public let corrected: UserText
    public let errors: [CorrectionError]
    public let suggestions: [CorrectionError]
    public let diff: [DiffSegment]
    public let warnings: [String]
    public let hasNoErrors: Bool
}

public enum CorrectionFailure: Error, Equatable {
    /// The text is in a language that is not enabled. Nothing was sent.
    case notEnabled(LanguageCode)
    /// Detection could not tell, and there is more than one candidate: ask
    /// which (#81). Nothing was sent.
    case needsLanguage([LanguageCode])
    /// The reply did not parse. Never shown as a correction (`FR-COR-06`).
    case unreadableReply
    /// The block count was wrong twice. Never stitched together.
    case structureLost
    case emptyResponse
}

/// German text in, a checked correction out (`FR-COR-01`..`06`).
///
/// Shaped like `Translator`. The differences are deliberate: parsing is
/// strict (a correction that cannot be read is never shown as one), a second
/// structural failure is an error rather than a joined text, and the result
/// is checked against itself before the user sees it.
public struct Corrector: Sendable {

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
    /// `language` is the text's language when the caller already knows it
    /// ("Which language is this?"); nil resolves it as `language(for:)`
    /// does, and fails with what that could not settle.
    public func correct(
        _ text: UserText, in language: LanguageCode? = nil, profile: AudienceProfile,
        styleNote: String? = nil
    ) -> LazyStream<CorrectionEvent> {
        LazyStream { [self] in
            AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        try await run(text, in: language, profile: profile, styleNote: styleNote) {
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

    private struct Context {
        let language: LanguageConfig
        let profile: AudienceProfile
        let styleNote: String?
        let terms: [String]
        let model: String
        let processor: PostProcessor
    }

    /// The language this text would be corrected in (#81): any enabled
    /// language, my own included; see `TextLanguage`.
    public func language(for text: UserText) -> TextLanguageResolution {
        TextLanguage.resolve(detector.detect(text.value), configuration: configuration, excludingMine: false)
    }

    /// The configured language to correct in, so its locale rules (ss for
    /// de-CH) and notes apply.
    private func textLanguage(_ text: UserText, given: LanguageCode?) throws -> LanguageConfig {
        var code: LanguageCode
        if let given {
            code = given
        } else {
            switch language(for: text) {
            case .known(let known): code = known
            case .mine(let mine): code = mine
            case .notEnabled(let other): throw CorrectionFailure.notEnabled(other)
            case .ask(let candidates): throw CorrectionFailure.needsLanguage(candidates)
            }
        }
        guard let language = configuration.language(for: code) else {
            throw CorrectionFailure.notEnabled(code)
        }
        guard language.enabled else { throw CorrectionFailure.notEnabled(code) }
        return language
    }

    private func run(
        _ text: UserText, in given: LanguageCode?, profile: AudienceProfile, styleNote: String?,
        emit: (CorrectionEvent) -> Void
    ) async throws {
        let language = try textLanguage(text, given: given)
        let context = Context(
            language: language, profile: profile, styleNote: styleNote,
            terms: configuration.doNotTranslate,
            model: configuration.model(for: .correct),
            processor: PostProcessor(target: language))
        emit(.started)

        let extracted = StructureExtractor.extract(text.value)
        let masked = extracted.blocks.map { TokenProtector.mask($0, terms: context.terms) }
        let first = try await generate(masked, context, emit)
        let response = try parse(first)

        let decision = BlockCountPolicy().decide(
            expected: extracted.skeleton.blockCount,
            received: response.correctedBlocks.count, attempt: 0)
        switch decision {
        case .accept:
            let finished = zip(response.correctedBlocks, masked).map {
                context.processor.finish($0, protected: $1)
            }
            let corrected = try StructureExtractor.reapply(
                finished.map(\.text), to: extracted.skeleton)
            emit(.finished(result(
                text, corrected, response.errors, masked.first,
                finished.flatMap(\.problems), context,
                masked.map(\.text).joined(separator: "\n"))))
        case .retryWholeText, .degrade:
            try await retryWholeText(text, context, emit)
        }
    }

    private func retryWholeText(
        _ text: UserText, _ context: Context, _ emit: (CorrectionEvent) -> Void
    ) async throws {
        let whole = TokenProtector.mask(text.value, terms: context.terms)
        let response = try parse(try await generate([whole], context, emit))
        guard response.correctedBlocks.count == 1 else { throw CorrectionFailure.structureLost }
        let finished = context.processor.finish(response.correctedBlocks[0], protected: whole)
        emit(.finished(result(
            text, finished.text, response.errors, whole, finished.problems, context, whole.text)))
    }

    private func generate(
        _ blocks: [ProtectedText], _ context: Context, _ emit: (CorrectionEvent) -> Void
    ) async throws -> String {
        let prompt = PromptBuilder().build(PromptRequest(
            action: .correct, source: context.language, target: context.language,
            profile: context.profile, doNotTranslate: context.terms,
            styleNote: context.styleNote, blocks: blocks.map(\.text), mine: configuration.mine))
        let raw = try await ReplyStream.collect(
            chat: chat, model: context.model, prompt: prompt, key: "corrected_blocks",
            onDelta: { emit(.progress) },
            onPartial: { emit(.preview(UserText(preview($0, blocks, context)))) })
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CorrectionFailure.emptyResponse
        }
        return raw
    }

    private func parse(_ raw: String) throws -> CorrectResponse {
        do {
            return try ResponseParser.parseCorrect(raw)
        } catch {
            throw CorrectionFailure.unreadableReply
        }
    }

    private func preview(
        _ partial: [String], _ blocks: [ProtectedText], _ context: Context
    ) -> String {
        partial.enumerated().map { index, block in
            guard index < blocks.count else { return block }
            return context.processor.finish(block, protected: blocks[index]).text
        }.joined(separator: "\n")
    }

    /// Assembles the result: fragments restored, the locale-rule additions,
    /// the split by severity, the check and the diff.
    ///
    /// `maskedText` -- the blocks the model actually saw, sentinels and all
    /// -- is what the locale-rule scan reads, never `original.value`: see
    /// `localeRuleErrors` for why.
    private func result(
        _ original: UserText, _ corrected: String, _ items: [CorrectionError],
        _ reference: ProtectedText?, _ problems: [ProtectionProblem], _ context: Context,
        _ maskedText: String
    ) -> CorrectionResult {
        let rules = context.language.localeRules
        let fixes = items.map { restore($0, reference, context) }
        var restored = fixes.map(\.displayed)
        restored += localeRuleErrors(in: maskedText, fixes: fixes, language: context.language)
        let verdict = CorrectionCheck.check(
            original: original.value, corrected: corrected, items: restored, rules: rules)
        return CorrectionResult(
            original: original,
            corrected: UserText(corrected),
            errors: restored.filter { $0.severity == .error },
            suggestions: restored.filter { $0.severity == .suggestion },
            diff: WordDiff.diff(original.value, corrected),
            warnings: warnings(problems) + verdict.warnings,
            hasNoErrors: verdict.hasNoErrors)
    }

    /// One item, restored, in both the form the user sees and the form
    /// coverage counting reads. Kept apart because they must never be
    /// conflated: `correctedUnnormalised` is what the model actually wrote,
    /// sentinels restored and nothing else, while `displayed.corrected` has
    /// also been through the locale rules -- see `restore` below.
    private struct RestoredFix {
        let displayed: CorrectionError
        let correctedUnnormalised: String
    }

    /// Sentinels inside a fragment come back as their terms. Every block is
    /// masked with the same ordered term list, so any one block's
    /// `ProtectedText` restores sentinels from all of them.
    ///
    /// `corrected` is restored once, then two things are built from that one
    /// restored value: the locale rules are applied for `displayed` -- the
    /// same protected ranges `context.processor.finish` would use, so a
    /// listed fix is never shown with a spelling the corrected text no
    /// longer has, and a restored do-not-translate term's own spelling is
    /// never rewritten -- while `correctedUnnormalised` is kept exactly as
    /// restored, with no rule pass, for `localeRuleErrors` to count against.
    /// That split matters: the locale rules rewrite every unprotected span
    /// regardless of whether the model's own edit touched it, so counting
    /// coverage against the *displayed* value would credit an item that
    /// merely quotes an untouched word with having fixed it.
    /// `original` is left exactly as the user wrote it.
    private func restore(
        _ item: CorrectionError, _ reference: ProtectedText?, _ context: Context
    ) -> RestoredFix {
        let original = unmasked(item.original, reference)
        let correctedRestored = unmaskedWithRanges(item.corrected, reference)
        let displayCorrected = LocaleRuleApplier.apply(
            context.language.localeRules, to: correctedRestored.text,
            protecting: correctedRestored.ranges)
        let displayed = CorrectionError(
            original: original, corrected: displayCorrected,
            category: item.category, explanation: item.explanation,
            severity: item.severity)
        return RestoredFix(displayed: displayed, correctedUnnormalised: correctedRestored.text)
    }

    private func unmasked(_ fragment: String, _ reference: ProtectedText?) -> String {
        guard let reference else { return fragment }
        return TokenProtector.restore(fragment, from: reference).text
    }

    /// As `unmasked`, but also returns the ranges the restored term(s) landed
    /// at, so the locale rules can be applied to the same fragment while
    /// protecting them -- exactly what `PostProcessor.finish` does, except
    /// this also hands back the pre-rule text for coverage counting.
    private func unmaskedWithRanges(
        _ fragment: String, _ reference: ProtectedText?
    ) -> (text: String, ranges: [Range<String.Index>]) {
        guard let reference else { return (fragment, []) }
        let restored = TokenProtector.restore(fragment, from: reference)
        return (restored.text, restored.protectedRanges)
    }

    /// A locale rule that rewrites the user's own text is a real correction,
    /// so it is listed and explained, never left as an unexplained change in
    /// the diff. For de-CH: the eszett.
    ///
    /// Scans the masked text -- the blocks actually sent, sentinels in place
    /// of every protected term -- rather than the raw original. A do-not-
    /// translate term is never rewritten (`PostProcessor.finish` leaves a
    /// restored protected span untouched), so a rule character sitting
    /// inside one, such as the eszett in "Weissenburg", must never be read
    /// as the user's own spelling: the sentinel hides it from this scan the
    /// same way it hides the term from the model.
    ///
    /// Skips the kit's row only when the model's own listed items, between
    /// them, removed at least as many occurrences of the rule's character as
    /// the masked text contains. Counting occurrences rather than checking
    /// mere containment matters: an item can easily contain both the rule's
    /// character -- in a word it left untouched -- and its replacement --
    /// inside some other word entirely, such as "besser" -- and containment
    /// alone would then treat an unrelated item as already explaining an
    /// eszett it never touched, silently dropping the kit's only
    /// explanation for a change `PostProcessor` still makes.
    private func localeRuleErrors(
        in maskedText: String, fixes: [RestoredFix], language: LanguageConfig
    ) -> [CorrectionError] {
        language.localeRules.filter { rule in
            let total = occurrences(of: rule.replace, in: maskedText)
            guard total > 0 else { return false }
            let removed = fixes.reduce(0) { $0 + removedOccurrences(of: rule, by: $1) }
            return removed < total
        }.map { rule in
            CorrectionError(
                original: rule.replace, corrected: rule.with, category: .spelling,
                explanation: "\(language.displayName) writes \"\(rule.with)\", never \"\(rule.replace)\".",
                severity: .error)
        }
    }

    /// How many occurrences of the rule's character one item actually
    /// removed: the drop between its `original` and its restored-but-
    /// unnormalised `corrected` -- what the model itself wrote, not what
    /// `LocaleRuleApplier` would make of it -- floored at zero so an item
    /// that left the character alone, or added one, is never counted as
    /// negative coverage.
    private func removedOccurrences(of rule: LocaleRule, by fix: RestoredFix) -> Int {
        let before = occurrences(of: rule.replace, in: fix.displayed.original)
        guard before > 0 else { return 0 }
        let after = occurrences(of: rule.replace, in: fix.correctedUnnormalised)
        return max(0, before - after)
    }

    private func occurrences(of substring: String, in text: String) -> Int {
        guard !substring.isEmpty else { return 0 }
        var count = 0
        var searchStart = text.startIndex
        while let found = text.range(of: substring, range: searchStart..<text.endIndex) {
            count += 1
            searchStart = found.upperBound
        }
        return count
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
