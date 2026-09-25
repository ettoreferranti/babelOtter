import Foundation

/// The `blocks` of a translate reply that is still arriving.
///
/// The model streams one JSON object, and nothing in it parses until the
/// closing brace. On a 24B local model that is seconds of a frozen popup. This
/// reads what has arrived: every finished string in the array, plus the one
/// still being written.
///
/// Only ever a preview. The result always comes from `ResponseParser` on the
/// complete reply, so a misreading here costs a flicker, never a wrong paste.
public enum PartialTranslateBlocks {

    public static func extract(from partial: String) -> [String] {
        guard let key = partial.range(of: "\"blocks\"") else { return [] }
        let scalars = Array(partial[key.upperBound...].unicodeScalars)

        var index = skipWhitespace(scalars, from: 0)
        guard index < scalars.count, scalars[index] == ":" else { return [] }
        index = skipWhitespace(scalars, from: index + 1)
        guard index < scalars.count, scalars[index] == "[" else { return [] }
        index += 1

        var blocks: [String] = []
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\"" {
                let read = readString(scalars, from: index + 1)
                blocks.append(read.text)
                guard read.closed else { break }
                index = read.next
            } else if scalar == "," || scalar.properties.isWhitespace {
                index += 1
            } else {
                // `]`, or anything that is not a string: the array is over,
                // or is not the shape a preview can use.
                break
            }
        }
        return blocks
    }

    private static func skipWhitespace(_ scalars: [Unicode.Scalar], from start: Int) -> Int {
        var index = start
        while index < scalars.count {
            guard scalars[index].properties.isWhitespace else { break }
            index += 1
        }
        return index
    }

    /// A JSON string body, starting just after its opening quote.
    private static func readString(
        _ scalars: [Unicode.Scalar], from start: Int
    ) -> (text: String, next: Int, closed: Bool) {
        var text = String.UnicodeScalarView()
        var index = start
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\"" {
                return (String(text), index + 1, true)
            }
            if scalar != "\\" {
                text.append(scalar)
                index += 1
                continue
            }
            // An escape that has not fully arrived is left out, not guessed.
            guard index + 1 < scalars.count else { break }
            let code = scalars[index + 1]
            if code == "u" {
                guard let decoded = unicodeEscape(scalars, at: index + 2) else { break }
                text.append(decoded.scalar)
                index = decoded.next
            } else {
                text.append(simpleEscape(code))
                index += 2
            }
        }
        return (String(text), index, false)
    }

    private static func simpleEscape(_ code: Unicode.Scalar) -> Unicode.Scalar {
        switch code {
        case "n": return "\n"
        case "t": return "\t"
        case "r": return "\r"
        case "b": return "\u{08}"
        case "f": return "\u{0C}"
        default: return code
        }
    }

    private static let replacement: Unicode.Scalar = "\u{FFFD}"

    /// `\uXXXX`, including a surrogate pair written as two escapes. `nil`
    /// while the escape is still incomplete.
    private static func unicodeEscape(
        _ scalars: [Unicode.Scalar], at start: Int
    ) -> (scalar: Unicode.Scalar, next: Int)? {
        guard let high = hex4(scalars, at: start) else { return nil }
        guard (0xD800...0xDBFF).contains(high) else {
            return (Unicode.Scalar(high) ?? replacement, start + 4)
        }
        // A high surrogate means nothing without its low half.
        guard start + 5 < scalars.count else { return nil }
        guard scalars[start + 4] == "\\", scalars[start + 5] == "u" else {
            return (replacement, start + 4)
        }
        guard let low = hex4(scalars, at: start + 6) else { return nil }
        let combined = 0x10000 + ((high - 0xD800) << 10) + (low &- 0xDC00)
        return (Unicode.Scalar(combined) ?? replacement, start + 10)
    }

    private static func hex4(_ scalars: [Unicode.Scalar], at start: Int) -> UInt32? {
        guard start + 4 <= scalars.count else { return nil }
        var value: UInt32 = 0
        for scalar in scalars[start..<start + 4] {
            guard let digit = UInt32(String(scalar), radix: 16) else { return nil }
            value = value * 16 + digit
        }
        return value
    }
}
