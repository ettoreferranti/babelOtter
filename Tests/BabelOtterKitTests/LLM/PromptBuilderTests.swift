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
        #expect(builder.build(request(doNotTranslate: ["ZHAW"])).contains("⟦DNT0⟧"))
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

    @Test("a prompt has no blank section left by an omitted part")
    func noDoubleBlankLines() {
        #expect(!builder.build(request()).contains("\n\n\n"))
    }
}
