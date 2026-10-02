import Foundation

/// Where a phrase occurs in a text, by character offset.
///
/// Scoring compares phrases the golden set names ("jetz", "eine Saetze")
/// with what a model wrote. Plain substring search is wrong for that: the
/// correct "jetzt" contains the wrong "jetz", so a fix would never count as
/// found. Whole-word search is what every scorer uses unless it says
/// otherwise.
enum TextSearch {

    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// Every occurrence of `needle` in `text`, overlapping ones included.
    ///
    /// With `wholeWords`, an occurrence must not touch a letter or digit on
    /// a side where the needle itself begins or ends with one. A needle that
    /// starts with punctuation (", und") needs no boundary before it.
    static func occurrences(of needle: String, in text: String, wholeWords: Bool) -> [Range<Int>] {
        let haystack = Array(text)
        let pattern = Array(needle)
        guard let first = pattern.first, let last = pattern.last, pattern.count <= haystack.count
        else { return [] }
        var found: [Range<Int>] = []
        for start in 0...(haystack.count - pattern.count) {
            let end = start + pattern.count
            guard haystack[start..<end].elementsEqual(pattern) else { continue }
            if wholeWords && touchesWord(haystack, start, end, first, last) { continue }
            found.append(start..<end)
        }
        return found
    }

    /// Whether `needle` occurs in `text` as whole words.
    static func contains(_ needle: String, in text: String) -> Bool {
        !occurrences(of: needle, in: text, wholeWords: true).isEmpty
    }

    static func wordCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for character in text {
            let isWord = isWordCharacter(character)
            if isWord && !inWord { count += 1 }
            inWord = isWord
        }
        return count
    }

    private static func touchesWord(
        _ haystack: [Character], _ start: Int, _ end: Int, _ first: Character, _ last: Character
    ) -> Bool {
        let before = start > 0 && isWordCharacter(first) && isWordCharacter(haystack[start - 1])
        let after = end < haystack.count && isWordCharacter(last) && isWordCharacter(haystack[end])
        return before || after
    }
}
