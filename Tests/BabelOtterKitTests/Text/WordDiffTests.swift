import Testing

@testable import BabelOtterKit

@Suite("Word-level diff", .timeLimit(.minutes(1)))
struct WordDiffTests {

    /// Both reconstructions must hold for every diff, or the popup shows a
    /// text that is not the one Replace pastes.
    private func expectRoundTrips(_ original: String, _ revised: String) {
        let segments = WordDiff.diff(original, revised)
        var left = ""
        var right = ""
        for segment in segments {
            switch segment {
            case .same(let text): left += text; right += text
            case .removed(let text): left += text
            case .added(let text): right += text
            }
        }
        #expect(left == original)
        #expect(right == revised)
    }

    @Test("identical texts are one unchanged segment")
    func identical() {
        #expect(WordDiff.diff("Guten Tag", "Guten Tag") == [.same("Guten Tag")])
    }

    @Test("a substituted word is removed then added, the rest unchanged")
    func substitution() {
        #expect(WordDiff.diff("mit der Kollege", "mit dem Kollegen") == [
            .same("mit "), .removed("der"), .added("dem"), .same(" "),
            .removed("Kollege"), .added("Kollegen"),
        ])
    }

    @Test("a pure insertion")
    func insertion() {
        #expect(WordDiff.diff("Ich gehe", "Ich gehe heute") == [
            .same("Ich gehe"), .added(" heute"),
        ])
    }

    @Test("a pure deletion")
    func deletion() {
        #expect(WordDiff.diff("Ich gehe heute", "Ich gehe") == [
            .same("Ich gehe"), .removed(" heute"),
        ])
    }

    @Test("punctuation is its own token")
    func punctuation() {
        #expect(WordDiff.diff("Ja das stimmt", "Ja, das stimmt") == [
            .same("Ja"), .added(","), .same(" das stimmt"),
        ])
    }

    @Test("umlauts and eszett stay inside their word")
    func umlauts() {
        #expect(WordDiff.diff("gr\u{00F6}\u{00DF}er", "gr\u{00F6}sser") == [
            .removed("gr\u{00F6}\u{00DF}er"), .added("gr\u{00F6}sser"),
        ])
    }

    @Test("empty on either side")
    func empty() {
        #expect(WordDiff.diff("", "") == [])
        #expect(WordDiff.diff("", "neu") == [.added("neu")])
        #expect(WordDiff.diff("alt", "") == [.removed("alt")])
    }

    @Test("both texts can always be rebuilt from the diff", arguments: [
        ("mit der Kollege", "mit dem Kollegen"),
        ("Ich gehe", "Ich gehe heute"),
        ("Ja das stimmt", "Ja, das stimmt"),
        ("Er hat gestern das Buch gelesen.", "Gestern hat er das Buch gelesen."),
        ("  zwei  Leerzeichen ", " zwei Leerzeichen"),
        ("line one\nline two", "line one\n\nline two"),
        ("", "neu"),
        // Just under WordDiff.maximumTokens: the trimmed middle still goes
        // through the LCS table, not the size fallback.
        (String(repeating: "a ", count: 500), String(repeating: "b ", count: 500)),
        // Just over WordDiff.maximumTokens: the trimmed middle is too big
        // for either cap and takes the removed-then-added fallback.
        (String(repeating: "a ", count: 5_000), String(repeating: "b ", count: 5_000)),
    ])
    func roundTrips(_ original: String, _ revised: String) {
        expectRoundTrips(original, revised)
    }

    @Test("adjacent segments of the same kind are merged")
    func merged() {
        // No token in common: one removal, and the three added tokens
        // ("y", " ", "z") merged into one addition.
        #expect(WordDiff.diff("x", "y z") == [.removed("x"), .added("y z")])
    }

    /// Pins the fix for #41: a lopsided pair (one short side, one huge side)
    /// used to be quadratic in the merge step even though the LCS table
    /// itself stayed small, because merging built each run by re-concatenating
    /// `x + y` one token at a time. The size fallback plus the amortised
    /// accumulator both keep this linear.
    ///
    /// The suite's one-minute time limit alone does not discriminate here: a
    /// reintroduced quadratic merge still finishes well under a minute at a
    /// merely large size, so it would pass, slowly, instead of failing. The
    /// explicit five-second bound below is the actual tripwire; 1,000,000 is
    /// chosen so the old, quadratic merge clears neither that bound nor the
    /// suite limit (see the fix round 2 report for measured timings).
    @Test("a lopsided diff against a huge side stays fast")
    func lopsided() {
        let start = ContinuousClock.now
        expectRoundTrips("x", String(repeating: "y ", count: 1_000_000))
        #expect(start.duration(to: .now) < .seconds(5))
    }
}
