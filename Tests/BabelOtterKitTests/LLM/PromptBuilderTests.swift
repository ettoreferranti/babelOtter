import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Prompt composition")
struct PromptBuilderTests {

    private let builder = PromptBuilder()
    private let enToDe = LanguagePair(source: LanguageCode("en"), target: LanguageCode("de-ch"))

    private func request(
        action: Action = .translate,
        target: LanguageConfig = .swissGerman,
        profile: AudienceProfile = .administration,
        inferFrom: [AudienceProfile] = [],
        glossary: [GlossaryEntry] = [],
        doNotTranslate: [String] = [],
        styleNote: String? = nil,
        blocks: [String] = ["hello"]
    ) -> PromptRequest {
        PromptRequest(
            action: action,
            source: .english,
            target: target,
            profile: profile,
            inferAudienceFrom: inferFrom,
            glossary: glossary,
            doNotTranslate: doNotTranslate,
            styleNote: styleNote,
            blocks: blocks
        )
    }

    @Test("inferring lists every audience with its id and names the fallback")
    func inferringListsAudiences() {
        let prompt = builder.build(request(profile: .colleagues, inferFrom: AudienceProfile.shippedDefaults))
        for profile in AudienceProfile.shippedDefaults {
            #expect(prompt.contains("- \(profile.id): \(profile.name)"))
        }
        #expect(prompt.contains("Decide which of these audiences the text addresses"))
        #expect(prompt.contains(#"put "unclear" and write for "colleagues""#))
        #expect(prompt.contains("The topic alone is not a sign."))
        #expect(prompt.contains("reports what the text shows, not whom you write for"))
        #expect(prompt.contains(#""detected_audience": "...", "audience_evidence": "...", "blocks""#))
        #expect(prompt.contains(#"In "audience_evidence" copy the exact words of the text that show its reader"#))
        #expect(!prompt.contains("Audience: Colleagues."))
    }

    @Test("inferring keeps each audience's preferred terms")
    func inferringKeepsGlossaryBias() {
        var students = AudienceProfile.students
        students.glossaryBias = ["Modul", "Semester"]
        let prompt = builder.build(request(profile: .colleagues, inferFrom: [students, .colleagues]))
        #expect(prompt.contains("Prefers: Modul, Semester."))
        #expect(prompt.components(separatedBy: "Prefers:").count == 2, "only the audience that has them")
    }

    @Test("an empty list is the fixed audience, unchanged")
    func emptyListIsFixed() {
        let prompt = builder.build(request(profile: .students, inferFrom: []))
        #expect(prompt.contains("Audience: Students."))
        #expect(!prompt.contains("Decide which"))
        #expect(!prompt.contains("audience_evidence"))
    }

    @Test("Correct never infers")
    func correctNeverInfers() {
        let prompt = builder.build(request(action: .correct, profile: .students, inferFrom: AudienceProfile.shippedDefaults))
        #expect(!prompt.contains("Decide which"))
        #expect(prompt.contains("addressed to Students"))
    }

    @Test("both language display names appear")
    func namesBothLanguages() {
        let prompt = builder.build(request())
        #expect(prompt.contains("English"))
        #expect(prompt.contains("Swiss Standard German"))
    }

    @Test("translate names source and target; other actions name one language")
    func languageLineDiffersByAction() {
        let translate = builder.build(request(action: .translate))
        #expect(translate.contains("Source language: English."))
        #expect(translate.contains("Target language: Swiss Standard German."))

        let correct = builder.build(request(action: .correct))
        #expect(correct.contains("Language: English."))
        #expect(!correct.contains("Source language:"))
        #expect(!correct.contains("Target language:"))
    }

    @Test("the required output schema appears")
    func statesTheSchema() {
        #expect(builder.build(request()).contains("blocks"))
        #expect(builder.build(request()).contains("one JSON object"))
    }

    @Test("a de-CH target forbids ß explicitly")
    func forbidsEszett() {
        let prompt = builder.build(request(target: .swissGerman))
        #expect(prompt.contains("ß"))
        #expect(prompt.contains("ss"))
    }

    @Test("an English target says nothing about ß")
    func englishSaysNothingAboutEszett() {
        #expect(!builder.build(request(target: .english)).contains("ß"))
    }

    @Test("the profile's register and tone guidance appear")
    func includesProfile() {
        let prompt = builder.build(request(profile: .administration))
        #expect(prompt.contains("Sie"))
        #expect(prompt.contains(AudienceProfile.administration.toneGuidance))
        #expect(prompt.contains("Administration"))
    }

    @Test("an informal profile asks for du")
    func informalRegister() {
        #expect(builder.build(request(profile: .informal)).contains("du"))
    }

    @Test("a profile's glossary bias appears when it has one")
    func glossaryBias() {
        let biased = AudienceProfile(
            id: "biased", name: "Biased", register: .formal, toneGuidance: "Tone.",
            glossaryBias: ["Fachhochschule"])
        #expect(builder.build(request(profile: biased)).contains("Fachhochschule"))
    }

    @Test("glossary entries appear")
    func includesGlossary() {
        let entry = GlossaryEntry(source: "module", target: "Modul", pair: enToDe)
        let prompt = builder.build(request(glossary: [entry]))
        #expect(prompt.contains("module"))
        #expect(prompt.contains("Modul"))
    }

    @Test("an empty glossary emits no heading at all")
    func noEmptyGlossarySection() {
        #expect(!builder.build(request()).contains("Use these renderings"))
    }

    @Test("a style note appears verbatim")
    func includesStyleNote() {
        #expect(builder.build(request(styleNote: "keep it very short")).contains("keep it very short"))
    }

    @Test("no style note emits no heading")
    func noEmptyStyleNote() {
        #expect(!builder.build(request()).contains("Additional instruction"))
    }

    @Test("a whitespace-only style note is treated as absent")
    func blankStyleNote() {
        #expect(!builder.build(request(styleNote: "   \n ")).contains("Additional instruction"))
    }

    /// The schema must be the last instruction, so a style note cannot talk the
    /// model out of the required output shape.
    @Test("the style note appears before the schema")
    func styleNoteCannotOverrideTheSchema() throws {
        let prompt = builder.build(request(styleNote: "reply in plain prose please"))
        let note = try #require(prompt.range(of: "reply in plain prose please"))
        let schema = try #require(prompt.range(of: "one JSON object"))
        #expect(note.lowerBound < schema.lowerBound)
    }

    @Test("DNT instructions appear only when there are protected terms")
    func protectedTermInstructions() {
        #expect(builder.build(request(doNotTranslate: ["Otterbach"])).contains("⟦DNT0⟧"))
        #expect(!builder.build(request()).contains("⟦DNT0⟧"))
    }

    @Test("blocks are a JSON array, never numbered, and the count is stated (#103)")
    func blocksAsArray() throws {
        let prompt = builder.build(request(blocks: ["one", #"say "hi"/bye"#, "Gr\u{00FC}sse"]))
        #expect(prompt.contains("exactly 3 block"))
        #expect(prompt.hasSuffix("[\n\"one\",\n\"say \\\"hi\\\"/bye\",\n\"Gr\u{00FC}sse\"\n]"))
        #expect(!prompt.contains("1. one"))
        #expect(!prompt.contains("numbered"))
        let array = try #require(prompt.range(of: "[\n", options: .backwards))
        let decoded = try JSONDecoder().decode([String].self, from: Data(prompt[array.lowerBound...].utf8))
        #expect(decoded == ["one", #"say "hi"/bye"#, "Gr\u{00FC}sse"])
    }

    @Test("each action states its own schema")
    func schemaPerAction() {
        #expect(builder.build(request(action: .correct)).contains("corrected_blocks"))
        #expect(builder.build(request(action: .explain)).contains("summary"))
        #expect(builder.build(request(action: .repitch)).contains("blocks"))
    }

    @Test("the correction schema lists the whole error taxonomy")
    func correctionTaxonomy() {
        let prompt = builder.build(request(action: .correct))
        for category in ErrorCategory.allCases {
            #expect(prompt.contains(category.rawValue), "missing category \(category.rawValue)")
        }
    }

    @Test("correction is told to preserve voice and not invent changes")
    func correctionInstruction() {
        let prompt = builder.build(request(action: .correct))
        #expect(prompt.contains("voice"))
        #expect(prompt.contains("no errors"))
    }

    @Test("correction keeps the author's meaning and quotes originals exactly")
    func correctionKeepsMeaning() {
        let prompt = builder.build(request(action: .correct))
        #expect(prompt.contains("keeps the author's meaning"))
        #expect(prompt.contains("not by exchanging the noun"))
        #expect(prompt.contains("Quote each original fragment exactly"))
    }

    // MARK: - Formality per target language (#110)

    private let italian = LanguageConfig(
        code: LanguageCode("it"), displayName: "Italian", localeRules: [], enabled: true,
        addressForms: AddressForms(formal: "Lei", informal: "tu"))

    @Test("into a language with forms, the reader is addressed with its form")
    func formsNamed() {
        #expect(builder.build(request(profile: .administration)).contains(#"Address the reader as "Sie"."#))
        #expect(builder.build(request(profile: .colleagues)).contains(#"Address the reader as "du"."#))
        let intoItalian = builder.build(request(target: italian, profile: .administration))
        #expect(intoItalian.contains(#"Address the reader as "Lei"."#))
        #expect(!intoItalian.contains("Sie"))
    }

    @Test("into English, the register in words and no German pronoun")
    func registerInWords() {
        let formal = builder.build(request(target: .english, profile: .administration))
        #expect(formal.contains("Write in a formal register."))
        #expect(!formal.contains("Address the reader"))
        #expect(!formal.contains(#""Sie""#))
        #expect(formal.contains("Tone: \(AudienceProfile.administration.toneGuidance)"))
        let informal = builder.build(request(target: .english, profile: .colleagues))
        #expect(informal.contains("Write in an informal register."))
    }

    @Test("the inference list gives each audience's formality in the target's terms")
    func inferenceFormality() {
        let german = builder.build(request(inferFrom: [.students, .colleagues]))
        #expect(german.contains("Audiences (id: name, formality, tone):"))
        #expect(german.contains(#"- students: Students, formal ("Sie")."#))
        #expect(german.contains(#"- colleagues: Colleagues, informal ("du")."#))
        let english = builder.build(request(target: .english, inferFrom: [.students]))
        #expect(english.contains("- students: Students, formal. "))
        #expect(!english.contains(#""Sie""#))
    }

    @Test("Correct names the form, or the register for a language without forms")
    func correctFormality() {
        let noForms = LanguageConfig(code: LanguageCode("xx"), displayName: "X", localeRules: [], enabled: true)
        let prompt = builder.build(request(action: .correct, target: noForms, profile: .administration))
        #expect(prompt.contains("The text is addressed to Administration, and should be written in a formal register."))
        let casual = builder.build(request(action: .correct, target: noForms, profile: .informal))
        #expect(casual.contains("Both formal and informal address suit them"))
        #expect(!casual.contains("informal register"))
        #expect(prompt.contains("Writing informally is a register error."))
    }

    @Test("Correct: too informal is an error, too formal at most a suggestion (#122)")
    func registerOneWay() {
        let formal = builder.build(request(action: .correct, profile: .administration))
        #expect(formal.contains(#"Addressing them as "du" is a register error."#))
        #expect(!formal.contains("not an error"))
        let casual = builder.build(request(action: .correct, profile: .colleagues))
        #expect(casual.contains(
            "The text is addressed to Colleagues. Both formal and informal address suit them: "
                + "neither is an error, so keep the author's choice exactly as written."))
        #expect(casual.contains("Mixing formal and informal address in one text is a register error."))
        // Naming the informal form pulled Mistral to it ("Le" became "Ti").
        #expect(!casual.contains(#""du""#))
        #expect(!casual.contains(#""Sie""#))
        #expect(!casual.contains("A mismatch"))
    }

    @Test("the written language's notes reach every action that writes it (#123)")
    func writingNotes() {
        let dialect = "Never write Swiss German dialect"
        #expect(builder.build(request(action: .translate, profile: .informal)).contains(dialect))
        #expect(builder.build(request(action: .correct, profile: .informal)).contains(dialect))
        #expect(builder.build(request(action: .repitch, profile: .informal)).contains(dialect))
        #expect(!builder.build(request(action: .translate, target: .english)).contains(dialect))
        let blank = LanguageConfig(
            code: LanguageCode("xx"), displayName: "X", localeRules: [], enabled: true, writingNotes: " \n")
        let plain = LanguageConfig(code: LanguageCode("xx"), displayName: "X", localeRules: [], enabled: true)
        #expect(builder.build(request(target: blank)) == builder.build(request(target: plain)))
    }

    @Test("Correct's audience section is the register only")
    func correctAudienceIsRegisterOnly() {
        let prompt = builder.build(request(action: .correct, profile: .administration))
        #expect(prompt.contains(
            #"The text is addressed to Administration, who should be addressed as "Sie"."#))
        #expect(prompt.contains("is a register error."))
        #expect(!prompt.contains("Tone:"))
    }

    @Test("Translate keeps the tone line; Correct's meaning rule does not leak into it")
    func translateAudienceUnchanged() {
        let prompt = builder.build(request(action: .translate, profile: .administration))
        #expect(!prompt.contains("exchanging the noun"))
        #expect(prompt.contains("Tone:"))
    }

    @Test("a prompt has no blank section left by an omitted part")
    func noDoubleBlankLines() {
        #expect(!builder.build(request()).contains("\n\n\n"))
    }

    @Test("Correct applies errors only and lists suggestions unapplied")
    func correctErrorsOnly() {
        let prompt = builder.build(PromptRequest(
            action: .correct, source: .swissGerman, target: .swissGerman,
            profile: .administration, styleNote: "streng", blocks: ["Ich habe"]))
        #expect(prompt.contains("corrected_blocks applies only changes whose severity is \"error\""))
        #expect(prompt.contains("do not apply them to corrected_blocks"))
        #expect(prompt.contains("\"Sie\""))
        #expect(prompt.contains("streng"))
    }

    /// A tutoring explanation that names the wrong rule teaches the wrong
    /// rule. Measured 2026-09-30: a correct fix explained as "the gender of
    /// the pronoun du", which has no gender.
    @Test("Correct's explanations must name the rule that was broken")
    func correctExplanationsNameTheRule() {
        let prompt = builder.build(PromptRequest(
            action: .correct, source: .swissGerman, target: .swissGerman,
            profile: .colleagues, blocks: ["Ich habe"]))
        #expect(prompt.contains("names the specific rule that was broken"))
        #expect(prompt.contains("have no grammatical gender"))
    }

    /// The schema used to show "case|word order|..." and the model copied the
    /// pipe notation into its answer. Allowed values are listed as prose.
    @Test("Correct's schema lists allowed values without pipe notation")
    func correctSchemaAllowedValues() {
        let prompt = builder.build(PromptRequest(
            action: .correct, source: .swissGerman, target: .swissGerman,
            profile: .colleagues, blocks: ["Ich habe"]))
        #expect(!prompt.contains("case|word order"))
        #expect(!prompt.contains("error|suggestion"))
        #expect(prompt.contains("exactly one of: case, word order, gender, agreement, false friend, spelling, register, preposition, other"))
        #expect(prompt.contains("One item per error"))
        #expect(prompt.contains("shortest fragment that contains the error"))
        #expect(prompt.contains("Never add empty items"))
    }

    /// Measured 2026-10-05: "das Rezept" for a receipt and "sensible Loesung"
    /// for a sensible one came back unchanged in 3/3 runs. Both sentences are
    /// grammatical, so only a check of each word's meaning finds them. The
    /// rule names no example: example pairs teach the swap (see HANDOFF).
    @Test("Correct checks each word's meaning, for false friends")
    func correctChecksMeaning() {
        let prompt = builder.build(PromptRequest(
            action: .correct, source: .swissGerman, target: .swissGerman,
            profile: .colleagues, blocks: ["Ich habe"]))
        #expect(prompt.contains("check what each word means in context"))
        #expect(prompt.contains("the meaning of a similar English word"))
        #expect(!prompt.contains("Rezept"))
        #expect(!prompt.contains("sensibel"))
    }

    @Test("the false-friend rule is Correct's alone")
    func falseFriendRuleIsCorrectOnly() {
        let prompt = builder.build(PromptRequest(
            action: .translate, source: .english, target: .swissGerman,
            profile: .colleagues, blocks: ["x"]))
        #expect(!prompt.contains("check what each word means in context"))
    }

    @Test("the explanation rule is Correct's alone")
    func explanationRuleIsCorrectOnly() {
        let prompt = builder.build(PromptRequest(
            action: .translate, source: .english, target: .swissGerman,
            profile: .colleagues, blocks: ["x"]))
        #expect(!prompt.contains("names the specific rule that was broken"))
    }

    @Test("the errors-only rule is Correct's alone")
    func errorsOnlyRuleIsCorrectOnly() {
        let prompt = builder.build(PromptRequest(
            action: .translate, source: .english, target: .swissGerman,
            profile: .colleagues, blocks: ["x"]))
        #expect(!prompt.contains("corrected_blocks applies only"))
    }

    @Test("a correction item can be built in code")
    func correctionErrorInit() {
        let item = CorrectionError(
            original: "a", corrected: "b", category: .spelling,
            explanation: "why", severity: .error)
        #expect(item.corrected == "b")
    }

    private func languageRequest(
        _ action: Action, text: LanguageConfig, into target: LanguageConfig, mine: LanguageConfig = .english
    ) -> PromptRequest {
        PromptRequest(
            action: action, source: text, target: target, profile: .colleagues, blocks: ["x"], mine: mine)
    }

    @Test("Spanish: Correct carries its notes, and a formal audience names usted (#132)")
    func spanish() {
        let correct = builder.build(languageRequest(.correct, text: .spanish, into: .spanish))
        #expect(correct.contains("quiero que vengas"))
        #expect(correct.contains("Spanish"))
        let translate = builder.build(PromptRequest(
            action: .translate, source: .english, target: .spanish, profile: .administration, blocks: ["x"]))
        #expect(translate.contains("usted"))
        let informal = builder.build(PromptRequest(
            action: .translate, source: .english, target: .spanish, profile: .informal, blocks: ["x"]))
        #expect(informal.contains("t\u{00FA}"))
    }

    @Test("Correct on a learned language: the learner framing, its notes, explanations in my language (#81)")
    func correctLearned() {
        let german = builder.build(languageRequest(.correct, text: .swissGerman, into: .swissGerman))
        #expect(german.contains("The author is learning Swiss Standard German and often thinks in English"))
        #expect(german.contains("A Swiss Standard German word used with the meaning of a similar English word"))
        // Inside the instruction, not a section of their own: as a separate
        // "Notes" section they read as a checklist, and Mistral began
        // changing "Herr" to "Frau" in a clean letter.
        #expect(german.contains("it connects. Resolve case errors by changing articles"))
        #expect(!german.contains("Notes on"))
        #expect(german.contains("\"mit der Lehrer\" becomes \"mit dem Lehrer\""))
        #expect(german.contains("Write each explanation in English."))
        #expect(!german.contains("native speaker"))

        let french = builder.build(languageRequest(.correct, text: .french, into: .french, mine: .italian))
        #expect(french.contains("The author is learning French and often thinks in Italian"))
        #expect(french.contains("it connects. Check the agreement of past participles"))
        #expect(french.contains("participle"))
        #expect(!french.contains("Lehrer"))
        #expect(french.contains("Write each explanation in Italian."))
        #expect(french.contains(
            "The examples above are in English; write your explanations in Italian. If there are no errors"))
        #expect(!german.contains("The examples above are in English"))
    }

    @Test("Correct on my own language: a native speaker, no false friends, no notes when none ship")
    func correctMine() {
        let english = builder.build(languageRequest(.correct, text: .english, into: .english))
        #expect(english.contains("The author is a native speaker of English"))
        #expect(english.contains("do not treat regional usage as an error"))
        #expect(!english.contains("is learning"))
        #expect(!english.contains("Notes on"))
        let italian = builder.build(languageRequest(.correct, text: .italian, into: .italian, mine: .italian))
        #expect(italian.contains("The author is a native speaker of Italian"))
        #expect(italian.contains("it connects. Check articulated prepositions"))
        #expect(italian.contains("Write each explanation in Italian."))
    }

    @Test("notes from config.json become one tidy sentence in the instruction")
    func userNotesTidied() {
        func prompt(_ notes: String?) -> String {
            let language = LanguageConfig(
                code: LanguageCode("fr"), displayName: "French", localeRules: [], enabled: true,
                correctionNotes: notes)
            return builder.build(languageRequest(.correct, text: language, into: language))
        }
        #expect(prompt("Use vous for clients").contains("it connects. Use vous for clients. If there"))
        #expect(prompt("Use vous!\n\n").contains("it connects. Use vous! If there"))
        #expect(prompt("  \n").contains("it connects. If there are no errors"))
        #expect(prompt(nil).contains("it connects. If there are no errors"))
    }

    @Test("notes are Correct's only")
    func notesOnlyForCorrect() {
        for action in [Action.translate, .explain, .repitch] {
            let prompt = builder.build(languageRequest(action, text: .swissGerman, into: .english))
            #expect(!prompt.contains("mit dem Lehrer"), "\(action)")
        }
    }

    @Test("the reply keys name no language")
    func neutralKeys() {
        let correct = builder.build(languageRequest(.correct, text: .french, into: .french))
        #expect(correct.contains(#""explanation": "...""#))
        let explain = builder.build(languageRequest(.explain, text: .french, into: .english))
        #expect(explain.contains(#"{"summary": "...", "notes""#))
        #expect(!correct.contains("_en") && !explain.contains("_en"))
    }

    @Test("Explain names the text's language and explains in the target, my language (#81)")
    func explainLanguages() {
        let french = builder.build(languageRequest(.explain, text: .french, into: .italian, mine: .italian))
        #expect(french.contains("Explain the French text below in plain Italian"))
        #expect(french.contains("explain in Italian what it means"))
    }

    @Test("Explain asks for the meaning, and for notes on tricky phrases only, quoted exactly")
    func explainInstruction() {
        let prompt = builder.build(languageRequest(.explain, text: .swissGerman, into: .english))
        #expect(prompt.contains("Explain the Swiss Standard German text below in plain English"))
        #expect(prompt.contains("quote the phrase exactly as it is written in the text"))
        #expect(prompt.contains("Do not add notes for plain words."))
        #expect(prompt.contains("If nothing is tricky, notes is []."))
    }

    @Test("Explain has no audience section: the explanation is written for the user")
    func explainHasNoAudience() {
        let prompt = builder.build(request(action: .explain, profile: .students))
        #expect(!prompt.contains("Audience:"))
        #expect(!prompt.contains("Address the reader"))
        #expect(!prompt.contains("addressed to"))
    }

    private func repitch(_ profile: AudienceProfile = .administration) -> String {
        builder.build(PromptRequest(
            action: .repitch, source: .swissGerman, target: .swissGerman,
            profile: profile, blocks: ["Hallo"]))
    }

    @Test("Re-pitch rewrites for the audience in the same language and keeps every fact")
    func repitchInstruction() {
        let prompt = repitch()
        #expect(prompt.contains(
            "Rewrite the blocks below for the audience described, in the same language."))
        #expect(prompt.contains("Keep every fact: names, dates, times, numbers, places, links and requests."))
        #expect(prompt.contains("Do not translate."))
    }

    @Test("Re-pitch names one language, keeps its orthography, and writes for the fixed audience")
    func repitchSections() {
        var profile = AudienceProfile.administration
        profile.glossaryBias = ["Studiengang"]
        let prompt = repitch(profile)
        #expect(prompt.contains("Language: Swiss Standard German."))
        #expect(!prompt.contains("Target language"))
        #expect(prompt.contains("Never write"))
        #expect(prompt.contains("Audience: Administration."))
        #expect(prompt.contains("Prefer these terms where natural: Studiengang."))
    }

    @Test("Re-pitch asks for blocks only")
    func repitchSchema() {
        let prompt = repitch()
        #expect(prompt.contains(#"{"blocks": ["..."]}"#))
        #expect(!prompt.contains("detected_source"))
        #expect(!prompt.contains("detected_audience"))
    }
}
