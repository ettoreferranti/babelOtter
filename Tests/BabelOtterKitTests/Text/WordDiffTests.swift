import Testing

@testable import BabelOtterKit

@Suite("Word-level diff")
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
}
