import Foundation

/// One string field of a reply that is still arriving, once its value has
/// fully arrived (#52: `detected_audience`, shown before the translation
/// finishes). Nil while the value is still being written.
///
/// Like `PartialBlocks`, only a preview: the result always comes from
/// `ResponseParser` on the complete reply.
public enum PartialField {

    public static func string(named key: String, in partial: String) -> String? {
        guard let found = partial.range(of: "\"" + key + "\"") else { return nil }
        let scalars = Array(partial[found.upperBound...].unicodeScalars)
        var index = PartialBlocks.skipWhitespace(scalars, from: 0)
        guard index < scalars.count else { return nil }
        guard scalars[index] == ":" else { return nil }
        index = PartialBlocks.skipWhitespace(scalars, from: index + 1)
        guard index < scalars.count else { return nil }
        guard scalars[index] == "\"" else { return nil }
        let read = PartialBlocks.readString(scalars, from: index + 1)
        guard read.closed else { return nil }
        return read.text
    }
}
