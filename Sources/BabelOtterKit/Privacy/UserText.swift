import Foundation

/// Text belonging to the user — anything they selected, wrote, or got back.
///
/// NFR-P5: this must never reach a log. Swift cannot make interpolation a
/// compile error, so the defence is inverted instead: every textual
/// representation of this type is already redacted, and reading the real
/// content requires asking for ``value`` by name. The accidental path is safe;
/// the deliberate one is visible in review.
public struct UserText: Sendable, Equatable, Hashable {

    /// The real content. Referencing this in a logging context is a review
    /// finding — use ``summary(languageCode:action:)`` instead.
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    /// Grapheme-cluster count, so "👩‍👩‍👧" counts as one character.
    public var characterCount: Int { value.count }

    public var isEmpty: Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Loggable metadata about this text, carrying no part of it.
    public func summary(languageCode: String, action: String) -> UserTextSummary {
        UserTextSummary(
            characterCount: characterCount,
            languageCode: languageCode,
            action: action
        )
    }
}

extension UserText: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "⟨redacted \(characterCount) chars⟩" }
    public var debugDescription: String { description }
}

extension UserText: CustomReflectable {
    /// `Mirror(reflecting:)` and `dump(_:)` read stored properties directly —
    /// they do not consult `description`/`debugDescription` at all — so
    /// without this conformance, `dump(userText)` while debugging would print
    /// the real content despite every textual representation above being
    /// redacted. This closes that path by replacing the reflected children
    /// with the redacted representation only. ``value`` remains the
    /// deliberate, reviewable way to reach the real content; this only closes
    /// the *accidental* one.
    public var customMirror: Mirror {
        Mirror(self, children: ["redacted": description], displayStyle: .struct)
    }
}

/// What babelOtter is allowed to say about the user's text in a log.
public struct UserTextSummary: Sendable, Equatable, CustomStringConvertible {
    public let characterCount: Int
    public let languageCode: String
    public let action: String

    public var description: String {
        "\(action) \(languageCode) \(characterCount) chars"
    }
}
