import Testing

@testable import BabelOtterKit

@Suite("Eval: whole-word search")
struct TextSearchTests {

    @Test("a word is not found inside a longer word")
    func notInsideLongerWord() {
        #expect(TextSearch.occurrences(of: "jetz", in: "Ich bin jetzt da.", wholeWords: true).isEmpty)
        #expect(!TextSearch.contains("jetz", in: "Ich bin jetzt da."))
        #expect(!TextSearch.contains("Sätze", in: "Zwei Sätzen."))
        #expect(!TextSearch.contains("3", in: "Um 13 Uhr."))
        #expect(!TextSearch.contains("bin", in: "Ich binde."))
    }

    @Test("plain search finds a word inside a longer one")
    func plainFindsInside() {
        #expect(TextSearch.occurrences(of: "jetz", in: "jetzt", wholeWords: false) == [0..<4])
        #expect(TextSearch.occurrences(of: "\u{00DF}", in: "Stra\u{00DF}e", wholeWords: false) == [4..<5])
    }

    @Test("a whole word is found at the edges and next to punctuation")
    func edgesAndPunctuation() {
        #expect(TextSearch.occurrences(of: "jetz", in: "jetz", wholeWords: true) == [0..<4])
        #expect(TextSearch.occurrences(of: "jetz", in: "Bin jetz.", wholeWords: true) == [4..<8])
        #expect(TextSearch.occurrences(of: "eine Sätze", in: "(eine Sätze)", wholeWords: true) == [1..<11])
    }

    @Test("a needle that starts or ends with punctuation needs no boundary on that side")
    func punctuationEdge() {
        #expect(TextSearch.occurrences(of: ", und", in: "gut, und", wholeWords: true) == [3..<8])
        #expect(TextSearch.occurrences(of: "gut,", in: "gut,und", wholeWords: true) == [0..<4])
    }

    @Test("every occurrence is reported, in order")
    func everyOccurrence() {
        #expect(TextSearch.occurrences(of: "der", in: "der Hund, der Ball", wholeWords: true)
            == [0..<3, 10..<13])
    }

    @Test("an empty needle, or one longer than the text, is never found")
    func degenerate() {
        #expect(TextSearch.occurrences(of: "", in: "abc", wholeWords: false).isEmpty)
        #expect(TextSearch.occurrences(of: "abcd", in: "abc", wholeWords: false).isEmpty)
    }

    @Test("words are runs of letters or digits", arguments: [
        ("Ich habe 3 Sätze, ok.", 5),
        ("", 0),
        (" - ", 0),
        ("E-Mail", 2),
        ("Strasse", 1),
    ])
    func wordCount(text: String, expected: Int) {
        #expect(TextSearch.wordCount(text) == expected)
    }
}
