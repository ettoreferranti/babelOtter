import Testing

@testable import BabelOtterKit

@Suite("Word count, for Progress's rate per 100 words (#78)")
struct WordCountTests {

    @Test("words between whitespace, with a letter or digit", arguments: [
        ("", 0),
        ("   \n\t ", 0),
        ("Hallo", 1),
        ("Ich gehe morgen nach Hause.", 5),
        ("Zeile eins\nZeile zwei\r\n\tdrei", 5),
        ("- Punkt eins\n- Punkt 2", 4),
        ("\u{2013} \u{2022} ... !", 0),
        ("Gr\u{00FC}\u{00DF}e, l'ami: 42%", 3),
    ])
    func counts(_ text: String, _ expected: Int) {
        #expect(WordCount.of(text) == expected)
    }
}
