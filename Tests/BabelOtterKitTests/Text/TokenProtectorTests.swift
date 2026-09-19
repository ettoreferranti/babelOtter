import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Do-not-translate terms come back verbatim")
struct TokenProtectorTests {

    @Test("a term becomes a sentinel")
    func masksATerm() {
        let masked = TokenProtector.mask("ZHAW is here", terms: ["ZHAW"])
        #expect(masked.text == "⟦DNT0⟧ is here")
        #expect(masked.terms == ["ZHAW"])
    }

    @Test("every occurrence of a term uses that term's sentinel")
    func masksEveryOccurrence() {
        let masked = TokenProtector.mask("ZHAW and ZHAW", terms: ["ZHAW"])
        #expect(masked.text == "⟦DNT0⟧ and ⟦DNT0⟧")
        #expect(masked.terms == ["ZHAW"])
    }

    @Test("distinct terms get distinct sentinels")
    func distinctSentinels() {
        let masked = TokenProtector.mask("ZHAW and Moodle", terms: ["ZHAW", "Moodle"])
        #expect(masked.text.contains("⟦DNT0⟧"))
        #expect(masked.text.contains("⟦DNT1⟧"))
        #expect(masked.terms.count == 2)
    }

    @Test(
        "mask then restore is the identity",
        arguments: [
            "ZHAW is here",
            "ZHAW and ZHAW and Moodle",
            "nothing to protect",
            "ZHAW",
            "Leading ZHAW trailing",
        ]
    )
    func roundTrip(_ input: String) {
        let masked = TokenProtector.mask(input, terms: ["ZHAW", "Moodle"])
        let restored = TokenProtector.restore(masked.text, from: masked)
        #expect(restored.text == input)
        #expect(restored.problems.isEmpty)
    }

    @Test("the longest matching term wins")
    func longestMatchWins() {
        let masked = TokenProtector.mask(
            "ZHAW School rules", terms: ["ZHAW", "ZHAW School"])
        #expect(!masked.text.contains("School"))
        let restored = TokenProtector.restore(masked.text, from: masked)
        #expect(restored.text == "ZHAW School rules")
    }

    @Test("a term inside a longer word is not masked")
    func notInsideAWord() {
        // Deliberately "ITem" and not "Item": the latter is left alone by
        // case-sensitivity alone, so it would pass with the boundary check
        // deleted and prove nothing.
        #expect(TokenProtector.mask("ITem", terms: ["IT"]).text == "ITem")
    }

    @Test("a term at the end of a longer word is not masked either")
    func notAtTheEndOfAWord() {
        #expect(TokenProtector.mask("bIT", terms: ["IT"]).text == "bIT")
    }

    @Test("an umlaut counts as a word character, so IT in ITaer is left alone")
    func unicodeWordBoundary() {
        let masked = TokenProtector.mask("ITär", terms: ["IT"])
        #expect(masked.text == "ITär", "an ASCII-only boundary check would mask this")
    }

    @Test("a term at a punctuation boundary is masked")
    func punctuationIsABoundary() {
        let masked = TokenProtector.mask("(ZHAW).", terms: ["ZHAW"])
        #expect(masked.text == "(⟦DNT0⟧).")
    }

    @Test("matching is case-sensitive, because a DNT term is a proper noun")
    func caseSensitive() {
        let masked = TokenProtector.mask("zhaw", terms: ["ZHAW"])
        #expect(masked.text == "zhaw")
    }

    @Test("a sentinel the model destroyed is reported, not silently dropped")
    func missingSentinelReported() {
        let masked = TokenProtector.mask("ZHAW rules", terms: ["ZHAW"])
        let restored = TokenProtector.restore("the model rewrote everything", from: masked)
        #expect(restored.problems == [.sentinelMissing(index: 0, term: "ZHAW")])
    }

    @Test("sentinel debris left in the output is reported")
    func debrisReported() {
        let masked = TokenProtector.mask("ZHAW", terms: ["ZHAW"])
        let restored = TokenProtector.restore("⟦DNT0⟧ and ⟦DNT7⟧", from: masked)
        #expect(restored.text.contains("ZHAW"))
        #expect(restored.problems.contains { if case .sentinelDebris = $0 { true } else { false } })
    }

    @Test("restored ranges point at the restored terms")
    func restoredRangesArePositioned() {
        let masked = TokenProtector.mask("ZHAW ist gross", terms: ["ZHAW"])
        let restored = TokenProtector.restore(masked.text, from: masked)
        #expect(restored.protectedRanges.count == 1)
        #expect(String(restored.text[restored.protectedRanges[0]]) == "ZHAW")
    }

    @Test("several restored terms each get a range, in document order")
    func multipleRanges() {
        let masked = TokenProtector.mask("ZHAW and Moodle", terms: ["ZHAW", "Moodle"])
        let restored = TokenProtector.restore(masked.text, from: masked)
        #expect(restored.protectedRanges.count == 2)
        #expect(String(restored.text[restored.protectedRanges[0]]) == "ZHAW")
        #expect(String(restored.text[restored.protectedRanges[1]]) == "Moodle")
    }

    @Test("a repeated term yields a range per occurrence")
    func rangePerOccurrence() {
        let masked = TokenProtector.mask("ZHAW and ZHAW", terms: ["ZHAW"])
        let restored = TokenProtector.restore(masked.text, from: masked)
        #expect(restored.protectedRanges.count == 2)
    }

    @Test("no terms is a no-op with no problems")
    func noTerms() {
        let masked = TokenProtector.mask("plain text", terms: [])
        #expect(masked.text == "plain text")
        let restored = TokenProtector.restore(masked.text, from: masked)
        #expect(restored.text == "plain text")
        #expect(restored.problems.isEmpty)
        #expect(restored.protectedRanges.isEmpty)
    }

    @Test("a term that never appears is not reported as missing")
    func absentTermIsNotAProblem() {
        let masked = TokenProtector.mask("nothing here", terms: ["ZHAW"])
        let restored = TokenProtector.restore(masked.text, from: masked)
        #expect(restored.problems.isEmpty)
    }

    @Test("empty and whitespace-only terms are ignored rather than matching everywhere")
    func emptyTermsIgnored() {
        let masked = TokenProtector.mask("hello", terms: ["", "   "])
        #expect(masked.text == "hello")
    }
}
