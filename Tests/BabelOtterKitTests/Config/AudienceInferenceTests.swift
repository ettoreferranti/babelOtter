import Testing

@testable import BabelOtterKit

@Suite("The model's detected_audience, matched to a configured audience")
struct AudienceInferenceTests {

    let profiles = AudienceProfile.shippedDefaults

    @Test("an exact id matches, including the fallback's own id")
    func exactId() {
        #expect(AudienceInference.match("students", in: profiles) == .students)
        #expect(AudienceInference.match("colleagues", in: profiles) == .colleagues)
    }

    @Test("case and surrounding space do not matter")
    func caseAndSpace() {
        #expect(AudienceInference.match("  Students \n", in: profiles) == .students)
    }

    @Test("a name matches when no id does")
    func byName() {
        let team = AudienceProfile(id: "team", name: "My Team", register: .informal, toneGuidance: "Short.")
        #expect(AudienceInference.match("my team", in: profiles + [team]) == team)
    }

    @Test("an id wins over another audience's name")
    func idBeforeName() {
        let first = AudienceProfile(id: "x", name: "y", register: .formal, toneGuidance: "")
        let second = AudienceProfile(id: "y", name: "z", register: .formal, toneGuidance: "")
        #expect(AudienceInference.match("y", in: [first, second]) == second)
    }

    @Test("unclear, nothing, empty or unknown means the fallback")
    func noMatch() {
        #expect(AudienceInference.match(AudienceInference.unclear, in: profiles) == nil)
        #expect(AudienceInference.match(nil, in: profiles) == nil)
        #expect(AudienceInference.match("   ", in: profiles) == nil)
        #expect(AudienceInference.match("parents", in: profiles) == nil)
    }

    @Test("evidence counts only when the quote occurs in the text")
    func evidence() {
        let text = "Dear students,\n\nthe exam takes place on 12 January."
        #expect(AudienceInference.isEvidence("Dear students", in: text))
        #expect(AudienceInference.isEvidence("  dear   STUDENTS ", in: text))
        #expect(!AudienceInference.isEvidence("Dear colleagues", in: text))
        #expect(!AudienceInference.isEvidence(nil, in: text))
        #expect(!AudienceInference.isEvidence("", in: text))
        #expect(!AudienceInference.isEvidence("D", in: text))
    }

    @Test("line breaks in the text and the quote compare as single spaces")
    func evidenceAcrossLines() {
        #expect(AudienceInference.isEvidence("Hi Anna, the", in: "Hi Anna,\nthe PR is merged"))
    }

    @Test("the prompt's word for no sign is unclear")
    func unclearWord() {
        #expect(AudienceInference.unclear == "unclear")
    }
}
