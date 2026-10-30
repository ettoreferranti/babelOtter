import Foundation

/// How many words a text has, for Progress's rate per 100 words (#78).
///
/// Pieces between whitespace, counted when they hold a letter or a digit,
/// so a lone dash or a bullet is not a word.
public enum WordCount {

    public static func of(_ text: String) -> Int {
        var count = 0
        for piece in text.split(whereSeparator: \.isWhitespace) where isWord(piece) {
            count += 1
        }
        return count
    }

    static func isWord(_ piece: Substring) -> Bool {
        for character in piece where character.isLetter || character.isNumber {
            return true
        }
        return false
    }
}
