import Foundation

/// Everything one generation needs, gathered before any string is built.
public struct PromptRequest: Sendable {
    public let action: Action
    public let source: LanguageConfig
    public let target: LanguageConfig
    public let profile: AudienceProfile
    public let glossary: [GlossaryEntry]
    public let doNotTranslate: [String]
    public let styleNote: String?
    public let blocks: [String]

    public init(
        action: Action,
        source: LanguageConfig,
        target: LanguageConfig,
        profile: AudienceProfile,
        glossary: [GlossaryEntry] = [],
        doNotTranslate: [String] = [],
        styleNote: String? = nil,
        blocks: [String]
    ) {
        self.action = action
        self.source = source
        self.target = target
        self.profile = profile
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
        sections.append(contentsOf: [
            orthography(request),
            audience(request),
            glossarySection(request),
            protectedTerms(request),
            styleNote(request),
        ].compactMap { $0 })

        // The schema goes last, so it is the final instruction the model reads
        // and a style note asking for plain prose cannot override it.
        sections.append(schema(for: request.action))
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
                language, do not rewrite the message. If there are no errors, return \
                the text unchanged and an empty error list.
                """
        case .explain:
            return "You are a language teacher. Explain the numbered blocks below in English."
        case .repitch:
            return """
                You are an editor. Re-aim the numbered blocks below at a different \
                audience without changing their language or their facts.
                """
        }
    }

    private func languages(_ request: PromptRequest) -> String {
        request.action == .translate
            ? "Source language: \(request.source.displayName). Target language: \(request.target.displayName)."
            : "Language: \(request.source.displayName)."
    }

    /// Derived from the target's locale rules rather than from its code, so a
    /// language added by configuration gets the same treatment (`FR-LNG-01`).
    private func orthography(_ request: PromptRequest) -> String? {
        let rules = request.target.localeRules
        guard !rules.isEmpty else { return nil }
        let lines = rules.map { "- Never write “\($0.replace)”. Always write “\($0.with)”." }
        return (["Orthography for \(request.target.displayName):"] + lines)
            .joined(separator: "\n")
    }

    private func audience(_ request: PromptRequest) -> String? {
        let profile = request.profile
        var lines = [
            "Audience: \(profile.name).",
            "Address the reader as “\(profile.register.rawValue)”.",
            "Tone: \(profile.toneGuidance)",
        ]
        if !profile.glossaryBias.isEmpty {
            lines.append("Prefer these terms where natural: \(profile.glossaryBias.joined(separator: ", ")).")
        }
        return lines.joined(separator: "\n")
    }

    private func glossarySection(_ request: PromptRequest) -> String? {
        guard !request.glossary.isEmpty else { return nil }
        let lines = request.glossary.map { "- “\($0.source)” → “\($0.target)”" }
        return (["Use these renderings exactly:"] + lines).joined(separator: "\n")
    }

    private func protectedTerms(_ request: PromptRequest) -> String? {
        guard !request.doNotTranslate.isEmpty else { return nil }
        return """
            Some words are replaced by placeholders of the form ⟦DNT0⟧. Copy every \
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

    private func schema(for action: Action) -> String {
        let shape: String
        switch action {
        case .translate, .repitch:
            shape = #"{"detected_source": "…", "detected_audience": "…", "blocks": ["…"]}"#
        case .correct:
            shape = """
                {"corrected_blocks": ["…"], "errors": [{"original": "…", "corrected": "…", \
                "category": "case|word order|gender|agreement|false friend|spelling|register|\
                preposition|other", "explanation_en": "…", "severity": "error|suggestion"}]}
                """
        case .explain:
            shape = #"{"summary_en": "…", "notes": [{"phrase": "…", "explanation_en": "…"}]}"#
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
