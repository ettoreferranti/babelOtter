import Foundation

/// Everything one generation needs, gathered before any string is built.
public struct PromptRequest: Sendable {
    public let action: Action
    public let source: LanguageConfig
    public let target: LanguageConfig
    public let profile: AudienceProfile
    /// #52: when not empty, the model chooses the audience from these and
    /// `profile` is the fallback for a text with no clear sign. Correct
    /// ignores it.
    public let inferAudienceFrom: [AudienceProfile]
    public let glossary: [GlossaryEntry]
    public let doNotTranslate: [String]
    public let styleNote: String?
    public let blocks: [String]

    public init(
        action: Action,
        source: LanguageConfig,
        target: LanguageConfig,
        profile: AudienceProfile,
        inferAudienceFrom: [AudienceProfile] = [],
        glossary: [GlossaryEntry] = [],
        doNotTranslate: [String] = [],
        styleNote: String? = nil,
        blocks: [String]
    ) {
        self.action = action
        self.source = source
        self.target = target
        self.profile = profile
        self.inferAudienceFrom = inferAudienceFrom
        self.glossary = glossary
        self.doNotTranslate = doNotTranslate
        self.styleNote = styleNote
        self.blocks = blocks
    }
}

/// The one place every prompt is composed.
///
/// #42's whole point: prompt behaviour is testable when it lives in a single
/// type, and untestable when it is spread across four call sites that each
/// append "and please reply in JSON".
public struct PromptBuilder: Sendable {

    public init() {}

    public func build(_ request: PromptRequest) -> String {
        var sections: [String] = [
            instruction(for: request),
            languages(request),
        ]

        // A section with nothing in it is not harmless. An empty "Glossary:"
        // heading measurably degrades small local models, which treat it as a
        // constraint they have failed to satisfy.
        // `+=` rather than Array's bulk-append: NFR-P4's guard matches the
        // spelling that Data's URL-taking initialiser shares with it, and that
        // initialiser does reach the network. A guard that carved out
        // exceptions by call shape is one a real violation could hide behind,
        // so it is cheaper to avoid the spelling than to weaken the check.
        sections += [
            orthography(request),
            audience(request),
            glossarySection(request),
            protectedTerms(request),
            styleNote(request),
        ].compactMap { $0 }

        // The schema goes last, so it is the final instruction the model reads
        // and a style note asking for plain prose cannot override it.
        sections.append(schema(for: request))
        sections.append(blocks(request))

        return sections.joined(separator: "\n\n")
    }

    private func instruction(for request: PromptRequest) -> String {
        switch request.action {
        case .translate:
            return "You are a precise translator. Translate the numbered blocks below."
        case .correct:
            return """
                You are a patient language tutor. Correct the numbered blocks below, \
                preserving the author's intent, structure and voice. Correct the \
                language, do not rewrite the message. Fix each error with the \
                smallest change that keeps the author's meaning. Resolve agreement \
                and case errors by changing articles, pronouns and endings, not by \
                exchanging the noun: "mit der Lehrer" becomes "mit dem Lehrer", not \
                "mit der Lehrerin". Never change a person's gender, the number of \
                people or things, the tense, who the text is about, or any fact. \
                The author is learning German and often thinks in English, so \
                check what each word means in context, not only its grammar. \
                A German word used with the meaning of a similar English word, \
                so that the sentence does not say what the author means, is an \
                error: replace it with the German word for the intended meaning. \
                Quote each original fragment exactly as the author wrote it, \
                character for character, even where it breaks the orthography \
                rules; those rules apply to corrected_blocks and corrected only. \
                Each explanation_en names the specific rule that was broken and the \
                words it connects, for example: "Leiterin refers to Anna, a woman, \
                so the noun takes its feminine form" or "mit takes the dative, so der \
                becomes dem". Personal pronouns such as du, ich and wir have no \
                grammatical gender; never give a pronoun's gender as the reason. \
                If there are no errors, return \
                the text unchanged and an empty error list. corrected_blocks applies \
                only changes whose severity is "error". List stylistic suggestions in \
                errors with severity "suggestion", and do not apply them to \
                corrected_blocks.
                """
        case .explain:
            return """
                You are a language teacher. Explain the German text below in plain English \
                for a reader who does not fully follow it. In summary_en, say what the text \
                means as a whole. In notes, add one item for each idiom, unusual construction \
                or tricky phrase: quote the phrase exactly as it is written in the text, and \
                explain in English what it means and how it works. Do not add notes for plain \
                words. If nothing is tricky, notes is [].
                """
        case .repitch:
            return """
                You are an editor. Rewrite the numbered blocks below for the audience described, \
                in the same language. Change the form of address, the register and the tone to \
                suit that audience. Keep every fact: names, dates, times, numbers, places, links \
                and requests. Do not add or remove information. Do not translate.
                """
        }
    }

    /// Written as a guard rather than a ternary: muter's ternary operator
    /// mis-parses a condition ending in an enum member and emits
    /// `... == .translate?`, which does not compile. Mutant schemata put every
    /// mutant for a file in one binary, so that single bad mutant makes the
    /// whole file unmeasurable. Same class of bug as the comma-conjunction
    /// `while` noted in muter.conf.yml.
    private func languages(_ request: PromptRequest) -> String {
        guard request.action == .translate else {
            return "Language: \(request.source.displayName)."
        }
        return
            "Source language: \(request.source.displayName). "
            + "Target language: \(request.target.displayName)."
    }

    /// Derived from the target's locale rules rather than from its code, so a
    /// language added by configuration gets the same treatment (`FR-LNG-01`).
    private func orthography(_ request: PromptRequest) -> String? {
        let rules = request.target.localeRules
        guard !rules.isEmpty else { return nil }
        let lines = rules.map { #"- Never write "\#($0.replace)". Always write "\#($0.with)"."# }
        return (["Orthography for \(request.target.displayName):"] + lines)
            .joined(separator: "\n")
    }

    /// Written as a guard rather than a ternary on `request.action`: muter's
    /// ternary operator mis-parses a condition ending in an enum member (see
    /// the comment on `languages(_:)` above).
    private func audience(_ request: PromptRequest) -> String? {
        // #65: an explanation is written for the user, not for a reader.
        if request.action == .explain { return nil }
        let profile = request.profile
        guard request.action == .correct else {
            if !request.inferAudienceFrom.isEmpty {
                return inferredAudience(request)
            }
            var lines = [
                "Audience: \(profile.name).",
                #"Address the reader as "\#(profile.register.rawValue)"."#,
                "Tone: \(profile.toneGuidance)",
            ]
            if !profile.glossaryBias.isEmpty {
                lines.append("Prefer these terms where natural: \(profile.glossaryBias.joined(separator: ", ")).")
            }
            return lines.joined(separator: "\n")
        }
        return
            #"The text is addressed to \#(profile.name), who should be addressed as "\#(profile.register.rawValue)". "#
            + "A mismatch is a register error."
    }

    /// #52: the model picks the audience the text addresses and writes for
    /// it. `request.profile` is the fallback for a text with no clear sign.
    private func inferredAudience(_ request: PromptRequest) -> String {
        var lines = ["Audiences (id: name, form of address, tone):"]
        for profile in request.inferAudienceFrom {
            var line = #"- \#(profile.id): \#(profile.name), "\#(profile.register.rawValue)". \#(profile.toneGuidance)"#
            if !profile.glossaryBias.isEmpty {
                line += " Prefers: " + profile.glossaryBias.joined(separator: ", ") + "."
            }
            lines.append(line)
        }
        lines.append(
            "Decide which of these audiences the text addresses and write for it. "
                // Measured 2026-10-15: without this the default model always
                // picked an audience, from the topic, for a text naming no
                // reader at all.
                + "Only decide on an audience when the text itself shows who it is written to: "
                + "a greeting, a name, how the reader is addressed, or content only that "
                + "audience would receive. The topic alone is not a sign. "
                + #"Put its id in "detected_audience". If the text gives no clear sign, put ""#
                + AudienceInference.unclear
                + #"" and write for "\#(request.profile.id)". "#
                // Measured 2026-10-15: told to write for the fallback, the
                // model then named the fallback as what it had detected.
                + #""detected_audience" reports what the text shows, not whom you write for: "#
                + #"with no clear sign it is ""# + AudienceInference.unclear
                + #"", even though you then write for "\#(request.profile.id)". "#
                + #"In "audience_evidence" copy the exact words of the text that show its reader "#
                + #"(a greeting, a name), or "" when there are none."#)
        return lines.joined(separator: "\n")
    }

    /// `audience_evidence` only when the audience is inferred, and before
    /// `blocks`, so it arrives early in the stream.
    private func translateShape(_ request: PromptRequest) -> String {
        if request.inferAudienceFrom.isEmpty {
            return #"{"detected_source": "...", "detected_audience": "...", "blocks": ["..."]}"#
        }
        return #"{"detected_source": "...", "detected_audience": "...", "audience_evidence": "...", "blocks": ["..."]}"#
    }

    private func glossarySection(_ request: PromptRequest) -> String? {
        guard !request.glossary.isEmpty else { return nil }
        let lines = request.glossary.map { #"- "\#($0.source)" -> "\#($0.target)""# }
        return (["Use these renderings exactly:"] + lines).joined(separator: "\n")
    }

    private func protectedTerms(_ request: PromptRequest) -> String? {
        guard !request.doNotTranslate.isEmpty else { return nil }
        return """
            Some words are replaced by placeholders of the form \(TokenProtector.sentinel(0)). \
            Copy every \
            placeholder into your output exactly as it appears. Never translate, \
            reword, space out or renumber them.
            """
    }

    private func styleNote(_ request: PromptRequest) -> String? {
        guard let note = request.styleNote?.trimmingCharacters(in: .whitespacesAndNewlines),
            !note.isEmpty
        else { return nil }
        return "Additional instruction from the user: \(note)"
    }

    private func schema(for request: PromptRequest) -> String {
        let shape: String
        switch request.action {
        case .translate:
            shape = translateShape(request)
        case .repitch:
            // #66: the language and the audience are both known.
            shape = #"{"blocks": ["..."]}"#
        case .correct:
            // Allowed values as prose, never "a|b": the model copied that
            // notation into its answers (measured 2026-09-30).
            shape = """
                {"corrected_blocks": ["..."], "errors": [{"original": "...", "corrected": "...", \
                "category": "...", "explanation_en": "...", "severity": "..."}]}
                category is exactly one of: case, word order, gender, agreement, false friend, \
                spelling, register, preposition, other. severity is exactly one of: error, \
                suggestion. One item per error: if a sentence has two errors, list two items. \
                Quote the shortest fragment that contains the error, not the whole sentence. \
                Never add empty items; if there are no errors, errors is [].
                """
        case .explain:
            shape = #"{"summary_en": "...", "notes": [{"phrase": "...", "explanation_en": "..."}]}"#
        }
        return """
            Reply with one JSON object and nothing else, in exactly this shape:
            \(shape)
            """
    }

    /// Numbered, with the count stated, so the model can be held to it and
    /// ``BlockCountPolicy`` has something to check.
    private func blocks(_ request: PromptRequest) -> String {
        let numbered = request.blocks.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        return """
            Return exactly \(request.blocks.count) block(s), in the same order.

            \(numbered)
            """
    }
}
