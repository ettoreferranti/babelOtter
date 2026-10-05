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
            glossary: glossary,
            doNotTranslate: doNotTranslate,
            styleNote: styleNote,
            blocks: blocks
        )
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

    @Test("blocks are numbered and the count is stated")
    func numbersTheBlocks() {
        let prompt = builder.build(request(blocks: ["one", "two"]))
        #expect(prompt.contains("exactly 2 block"))
        #expect(prompt.contains("1. one"))
        #expect(prompt.contains("2. two"))
    }

    @Test("each action states its own schema")
    func schemaPerAction() {
        #expect(builder.build(request(action: .correct)).contains("corrected_blocks"))
        #expect(builder.build(request(action: .explain)).contains("summary_en"))
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

    @Test("Correct's audience section is the register only")
    func correctAudienceIsRegisterOnly() {
        let prompt = builder.build(request(action: .correct, profile: .administration))
        #expect(prompt.contains(
            #"The text is addressed to Administration, who should be addressed as "Sie"."#))
        #expect(prompt.contains("A mismatch is a register error."))
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
            explanationEn: "why", severity: .error)
        #expect(item.corrected == "b")
    }
}
