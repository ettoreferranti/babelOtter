import Foundation

/// The facts of a text a rewrite must keep (#66): numbers (dates, times,
/// decimals, ranges), web addresses and email addresses. `missing` lists
/// those of the original that the result does not contain as written.
///
/// A check, not a judgement: a reformatted time is reported too, because in
/// the same language there is no reason to reformat it.
public enum FactCheck {

    public static func missing(from original: String, in result: String) -> [String] {
        var missing: [String] = []
        for fact in facts(in: original) {
            if isKept(fact, in: result) { continue }
            if missing.contains(fact) { continue }
            missing.append(fact)
        }
        return missing
    }

    /// As written, or as a range or fraction whose parts all survive: a
    /// formal rewrite turns "14:30-15:00" into "von 14:30 bis 15:00 Uhr"
    /// and has lost nothing (final review, 2026-10-16).
    private static func isKept(_ fact: String, in result: String) -> Bool {
        if result.contains(fact) { return true }
        let parts = fact.split(whereSeparator: { $0 == "-" || $0 == "/" })
        if parts.count < 2 { return false }
        for part in parts {
            if !result.contains(part) { return false }
        }
        return true
    }

    static func facts(in text: String) -> [String] {
        var found: [String] = []
        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            if let link = link(in: Substring(word)) {
                found.append(link)
            } else {
                found += numbers(in: Array(word))
            }
        }
        return found
    }

    private static let opening: Set<Character> = ["(", "<", "[", "\"", "'"]
    private static let closing: Set<Character> = [".", ",", ";", ":", "!", "?", ")", ">", "]", "\"", "'"]
    private static let joiners: Set<Character> = [".", ",", ":", "/", "-"]

    /// A web or email address, without the punctuation around it.
    private static func link(in word: Substring) -> String? {
        var text = word
        while true {
            guard let first = text.first else { break }
            guard opening.contains(first) else { break }
            text = text.dropFirst()
        }
        while true {
            guard let last = text.last else { break }
            guard closing.contains(last) else { break }
            text = text.dropLast()
        }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") { return String(text) }
        if lower.hasPrefix("https://") { return String(text) }
        if lower.hasPrefix("www.") { return String(text) }
        if isEmail(text) { return String(text) }
        return nil
    }

    private static func isEmail(_ text: Substring) -> Bool {
        guard let at = text.firstIndex(of: "@") else { return false }
        guard at > text.startIndex else { return false }
        return text[text.index(after: at)...].contains(".")
    }

    /// Digit runs, joined into one fact by a single separator between digits.
    private static func numbers(in characters: [Character]) -> [String] {
        var found: [String] = []
        var index = 0
        while index < characters.count {
            if !isDigit(characters[index]) {
                index += 1
                continue
            }
            var end = index
            while end < characters.count {
                if isDigit(characters[end]) {
                    end += 1
                    continue
                }
                guard joiners.contains(characters[end]) else { break }
                guard end + 1 < characters.count else { break }
                guard isDigit(characters[end + 1]) else { break }
                end += 1
            }
            found.append(String(characters[index..<end]))
            index = end
        }
        return found
    }

    private static func isDigit(_ character: Character) -> Bool {
        character >= "0" && character <= "9"
    }
}
