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
    /// My language (#81): Correct's explanations are written in it, and its
    /// false friends are judged against it. Explain writes into `target`.
    public let mine: LanguageConfig

    public init(
        action: Action,
        source: LanguageConfig,
        target: LanguageConfig,
        profile: AudienceProfile,
        inferAudienceFrom: [AudienceProfile] = [],
        glossary: [GlossaryEntry] = [],
        doNotTranslate: [String] = [],
        styleNote: String? = nil,
        blocks: [String],
        mine: LanguageConfig = .english
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
        self.mine = mine
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
            writingNotes(request),
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
                exchanging the noun. Never change a person's gender, the number of \
                people or things, the tense, who the text is about, or any fact. \
                \(author(request)) \
                Quote each original fragment exactly as the author wrote it, \
                character for character, even where it breaks the orthography \
                rules; those rules apply to corrected_blocks and corrected only. \
                Write each explanation in \(request.mine.displayName). Each \
                explanation names the specific rule that was broken and the words \
                it connects. \(correctionNotes(request) ?? "")If there are no errors, return \
                the text unchanged and an empty error list. corrected_blocks applies \
                only changes whose severity is "error". List stylistic suggestions in \
                errors with severity "suggestion", and do not apply them to \
                corrected_blocks.
                """
        case .explain:
            let source = request.source.displayName
            let mine = request.target.displayName
            return """
                You are a language teacher. Explain the \(source) text below in plain \(mine) \
                for a reader who does not fully follow it. In summary, say what the text \
                means as a whole. In notes, add one item for each idiom, unusual construction \
                or tricky phrase: quote the phrase exactly as it is written in the text, and \
                explain in \(mine) what it means and how it works. Do not add notes for plain \
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

    /// Who wrote the text Correct reads (#81): a learner who thinks in my
    /// language, whose false friends are errors; or, in my own language, a
    /// native speaker, whose regional usage is not an error.
    private func author(_ request: PromptRequest) -> String {
        let text = request.source.displayName
        let mine = request.mine.displayName
        guard request.source.code != request.mine.code else {
            return "The author is a native speaker of \(text): correct slips and errors, "
                + "and do not treat regional usage as an error."
        }
        return "The author is learning \(text) and often thinks in \(mine), so check what each "
            + "word means in context, not only its grammar. A \(text) word used with the meaning "
            + "of a similar \(mine) word, so that the sentence does not say what the author means, "
            + "is an error: replace it with the \(text) word for the intended meaning."
    }

    /// The text's language's own notes for Correct (#81), from its
    /// configuration; nothing for another action or a language without notes.
    /// Spliced into the instruction, not given a section of their own: as a
    /// separate "Notes" section they read as a checklist, and Mistral changed
    /// "Herr" to "Frau" in a clean letter in every run (a #120 regression).
    private func correctionNotes(_ request: PromptRequest) -> String? {
        guard request.action == .correct else { return nil }
        guard let written = request.source.correctionNotes else { return nil }
        // Notes from config.json are any text: inside a sentence they need
        // no stray line breaks, and an end, or they run into the next one.
        let notes = written.trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.isEmpty { return nil }
        var heading = notes + " "
        if let last = notes.last {
            if !".!?\"".contains(last) { heading = notes + ". " }
        }
        // The shipped notes' example explanations are English; say so, or a
        // small model follows them rather than the explanation language.
        guard request.mine.code.baseSubtag != LanguageConfig.english.code else { return heading }
        return heading + "The examples above are in English; write your explanations in "
            + "\(request.mine.displayName). "
    }

    /// The written language's own notes (#123), for every action: told only
    /// "Swiss Standard German", Mistral wrote a casual text in dialect.
    private func writingNotes(_ request: PromptRequest) -> String? {
        guard let notes = request.target.writingNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        if notes.isEmpty { return nil }
        return notes
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
                Self.formality(profile.register, in: request.target),
                "Tone: \(profile.toneGuidance)",
            ]
            if !profile.glossaryBias.isEmpty {
                lines.append("Prefer these terms where natural: \(profile.glossaryBias.joined(separator: ", ")).")
            }
            return lines.joined(separator: "\n")
        }
        // Correct writes in the text's own language, its target: that
        // language's forms, or none. #122: only a text less formal than its
        // audience is wrong; a more formal one is polite, at most a suggestion.
        guard let forms = request.target.addressForms else {
            switch profile.register {
            case .formal:
                return "The text is addressed to \(profile.name), and should be written in "
                    + "\(profile.register.phrase). Writing informally is a register error."
            case .informal:
                return "The text is addressed to \(profile.name), and can be written in "
                    + "\(profile.register.phrase). " + Self.tooFormalIsFine("A more formal text")
            }
        }
        switch profile.register {
        case .formal:
            return #"The text is addressed to \#(profile.name), who should be addressed as "\#(forms.formal)". "#
                + #"Addressing them as "\#(forms.informal)" is a register error."#
        case .informal:
            return #"The text is addressed to \#(profile.name), who can be addressed as "\#(forms.informal)". "#
                + Self.tooFormalIsFine(#"Addressing them as "\#(forms.formal)""#)
        }
    }

    /// Measured for #122: told "a mismatch is a register error", Mistral
    /// turned a clean "Je vous reponds" to colleagues into "Je te reponds".
    /// Mixing both forms in one text is still an error.
    private static func tooFormalIsFine(_ subject: String) -> String {
        subject + " is not an error: list it as a register suggestion at most, "
            + "and leave it unchanged in corrected_blocks. Mixing formal and informal "
            + "address in one text is a register error."
    }

    /// The language's own form of address (#110), or, for a language
    /// without one (English), the register in words: formality still
    /// matters there, only no pronoun carries it.
    static func formality(_ register: Register, in language: LanguageConfig) -> String {
        guard let forms = language.addressForms else {
            return "Write in \(register.phrase)."
        }
        return #"Address the reader as "\#(forms.form(for: register))"."#
    }

    /// `formal ("Sie")`, or `formal` for a language without forms.
    private static func formalityLabel(_ register: Register, in language: LanguageConfig) -> String {
        guard let forms = language.addressForms else { return register.word }
        return #"\#(register.word) ("\#(forms.form(for: register))")"#
    }

    /// #52: the model picks the audience the text addresses and writes for
    /// it. `request.profile` is the fallback for a text with no clear sign.
    private func inferredAudience(_ request: PromptRequest) -> String {
        var lines = ["Audiences (id: name, formality, tone):"]
        for profile in request.inferAudienceFrom {
            let formality = Self.formalityLabel(profile.register, in: request.target)
            var line = "- \(profile.id): \(profile.name), \(formality). \(profile.toneGuidance)"
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
                "category": "...", "explanation": "...", "severity": "..."}]}
                category is exactly one of: case, word order, gender, agreement, false friend, \
                spelling, register, preposition, other. severity is exactly one of: error, \
                suggestion. One item per error: if a sentence has two errors, list two items. \
                Quote the shortest fragment that contains the error, not the whole sentence. \
                Never add empty items; if there are no errors, errors is [].
                """
        case .explain:
            shape = #"{"summary": "...", "notes": [{"phrase": "...", "explanation": "..."}]}"#
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
