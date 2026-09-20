import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Do-not-translate terms come back verbatim")
struct TokenProtectorTests {

    @Test("a term becomes a sentinel")
    func masksATerm() {
        let masked = TokenProtector.mask("Otterbach is here", terms: ["Otterbach"])
        #expect(masked.text == "⟦DNT0⟧ is here")
        #expect(masked.terms == ["Otterbach"])
    }

    @Test("every occurrence of a term uses that term's sentinel")
    func masksEveryOccurrence() {
        let masked = TokenProtector.mask("Otterbach and Otterbach", terms: ["Otterbach"])
        #expect(masked.text == "⟦DNT0⟧ and ⟦DNT0⟧")
        #expect(masked.terms == ["Otterbach"])
    }

    @Test("distinct terms get distinct sentinels")
    func distinctSentinels() {
        let masked = TokenProtector.mask("Otterbach and Moodle", terms: ["Otterbach", "Moodle"])
        #expect(masked.text.contains("⟦DNT0⟧"))
        #expect(masked.text.contains("⟦DNT1⟧"))
        #expect(masked.terms.count == 2)
    }

    @Test(
        "mask then restore is the identity",
        arguments: [
            "Otterbach is here",
            "Otterbach and Otterbach and Moodle",
            "nothing to protect",
            "Otterbach",
            "Leading Otterbach trailing",
        ]
    )
    func roundTrip(_ input: String) {
        let masked = TokenProtector.mask(input, terms: ["Otterbach", "Moodle"])
        let restored = TokenProtector.restore(masked.text, from: masked)
        #expect(restored.text == input)
        #expect(restored.problems.isEmpty)
    }

    @Test("the longest matching term wins")
    func longestMatchWins() {
        let masked = TokenProtector.mask(
            "Otterbach School rules", terms: ["Otterbach", "Otterbach School"])
        #expect(!masked.text.contains("School"))
        let restored = TokenProtector.restore(masked.text, from: masked)
        #expect(restored.text == "Otterbach School rules")
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
        let masked = TokenProtector.mask("(Otterbach).", terms: ["Otterbach"])
        #expect(masked.text == "(⟦DNT0⟧).")
    }

    @Test("matching is case-sensitive, because a DNT term is a proper noun")
    func caseSensitive() {
        let masked = TokenProtector.mask("otterbach", terms: ["Otterbach"])
        #expect(masked.text == "otterbach")
    }

    @Test("a sentinel the model destroyed is reported, not silently dropped")
    func missingSentinelReported() {
        let masked = TokenProtector.mask("Otterbach rules", terms: ["Otterbach"])
        let restored = TokenProtector.restore("the model rewrote everything", from: masked)
        #expect(restored.problems == [.sentinelMissing(index: 0, term: "Otterbach")])
    }

    @Test("sentinel debris left in the output is reported")
    func debrisReported() {
        let masked = TokenProtector.mask("Otterbach", terms: ["Otterbach"])
        let restored = TokenProtector.restore("⟦DNT0⟧ and ⟦DNT7⟧", from: masked)
        #expect(restored.text.contains("Otterbach"))
        #expect(restored.problems.contains { if case .sentinelDebris = $0 { true } else { false } })
    }

    @Test("restored ranges point at the restored terms")
    func restoredRangesArePositioned() {
        let masked = TokenProtector.mask("Otterbach ist gross", terms: ["Otterbach"])
        let restored = TokenProtector.restore(masked.text, from: masked)
        #expect(restored.protectedRanges.count == 1)
        #expect(String(restored.text[restored.protectedRanges[0]]) == "Otterbach")
    }

    @Test("several restored terms each get a range, in document order")
    func multipleRanges() {
        let masked = TokenProtector.mask("Otterbach and Moodle", terms: ["Otterbach", "Moodle"])
        let restored = TokenProtector.restore(masked.text, from: masked)
        #expect(restored.protectedRanges.count == 2)
        #expect(String(restored.text[restored.protectedRanges[0]]) == "Otterbach")
        #expect(String(restored.text[restored.protectedRanges[1]]) == "Moodle")
    }

    @Test("a repeated term yields a range per occurrence")
    func rangePerOccurrence() {
        let masked = TokenProtector.mask("Otterbach and Otterbach", terms: ["Otterbach"])
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
        let masked = TokenProtector.mask("nothing here", terms: ["Otterbach"])
        let restored = TokenProtector.restore(masked.text, from: masked)
        #expect(restored.problems.isEmpty)
    }

    // The term ordering is observable through `terms`, and it has to be: the
    // sentinel index is a position in this array, so a different order is a
    // different meaning for every sentinel already in flight.

    @Test("terms are ordered longest first, with ties in configured order")
    func termOrdering() {
        let masked = TokenProtector.mask("nothing", terms: ["bb", "a", "cc", "dddd"])
        #expect(masked.terms == ["dddd", "bb", "cc", "a"])
    }

    @Test("a duplicate term appears once")
    func duplicatesCollapse() {
        #expect(TokenProtector.mask("nothing", terms: ["Otterbach", "Otterbach"]).terms == ["Otterbach"])
    }

    @Test("an empty term is dropped even when it is not a duplicate")
    func emptyTermDropped() {
        #expect(TokenProtector.mask("nothing", terms: [""]).terms.isEmpty)
        #expect(TokenProtector.mask("nothing", terms: ["", "Otterbach"]).terms == ["Otterbach"])
        #expect(TokenProtector.mask("nothing", terms: ["  ", "Otterbach"]).terms == ["Otterbach"])
    }

    @Test("a sentinel index exactly at the term count is debris, not a term")
    func sentinelIndexAtBoundary() {
        let masked = TokenProtector.mask("Otterbach", terms: ["Otterbach"])
        let restored = TokenProtector.restore("⟦DNT1⟧", from: masked)
        #expect(restored.text == "⟦DNT1⟧")
        #expect(restored.problems.contains(.sentinelDebris("⟦DNT1⟧")))
        #expect(restored.protectedRanges.isEmpty)
    }

    @Test("sentinel index zero is a term, not debris")
    func sentinelIndexZeroIsATerm() {
        let masked = TokenProtector.mask("Otterbach", terms: ["Otterbach"])
        let restored = TokenProtector.restore("⟦DNT0⟧", from: masked)
        #expect(restored.text == "Otterbach")
        #expect(restored.problems.isEmpty)
    }

    @Test("a sentinel with no digits is left alone rather than parsed as index zero")
    func sentinelWithoutDigits() {
        let masked = TokenProtector.mask("Otterbach", terms: ["Otterbach"])
        let restored = TokenProtector.restore("⟦DNT⟧", from: masked)
        #expect(restored.text == "⟦DNT⟧")
    }

    @Test("empty and whitespace-only terms are ignored rather than matching everywhere")
    func emptyTermsIgnored() {
        let masked = TokenProtector.mask("hello", terms: ["", "   "])
        #expect(masked.text == "hello")
    }
}
