import Foundation

/// A directed translation direction. `en → de-ch` is not `de-ch → en`.
///
/// Direction is part of the key because `FR-GLO-01`'s glossary is bidirectional
/// but not symmetric: "module" → "Modul" is a rendering choice that says nothing
/// about how "Modul" should come back.
public struct LanguagePair: Sendable, Hashable, Codable {

    public let source: LanguageCode
    public let target: LanguageCode

    public init(source: LanguageCode, target: LanguageCode) {
        self.source = source
        self.target = target
    }
}

/// One forced rendering, injected into the prompt for its pair.
public struct GlossaryEntry: Sendable, Equatable, Codable {

    public let source: String
    public let target: String
    public let pair: LanguagePair

    public init(source: String, target: String, pair: LanguagePair) {
        self.source = source
        self.target = target
        self.pair = pair
    }
}

/// The user's terminology, filtered at the model rather than at the prompt.
///
/// `FR-GLO-01`. Filtering lives here so ``PromptBuilder`` cannot accidentally
/// include the other direction's entries — a prompt carrying both directions of
/// every term is how a small local model gets talked into translating a word it
/// was told to leave alone.
public struct Glossary: Sendable, Equatable, Codable {

    public var entries: [GlossaryEntry]

    public init(entries: [GlossaryEntry] = []) {
        self.entries = entries
    }

    /// Entries for exactly this direction, in configured order.
    public func entries(for pair: LanguagePair) -> [GlossaryEntry] {
        entries.filter { $0.pair == pair }
    }
}
