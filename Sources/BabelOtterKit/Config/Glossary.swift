import Foundation

/// A directed translation direction. `en -> de-ch` is not `de-ch -> en`.
///
/// Direction is part of the key because `FR-GLO-01`'s glossary is bidirectional
/// but not symmetric: "module" -> "Modul" is a rendering choice that says nothing
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

/// One term in every language that has it (#59): a row of the glossary.
///
/// Terms are trimmed and never empty; a language with no term is absent.
/// A term for a language that is not configured is kept, so editing the
/// row in the settings window does not lose it.
public struct GlossaryConcept: Sendable, Equatable, Codable {

    public private(set) var terms: [LanguageCode: String]

    public init(terms: [LanguageCode: String] = [:]) {
        self.terms = [:]
        for (language, term) in terms {
            set(term, for: language)
        }
    }

    public var isEmpty: Bool { terms.isEmpty }

    /// Trimmed; an empty term removes the language.
    public mutating func set(_ term: String, for language: LanguageCode) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            terms[language] = nil
        } else {
            terms[language] = trimmed
        }
    }

    /// `{"de-ch": "Modul", "en": "module"}`: an object by language code.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: LanguageKey.self)
        var terms: [LanguageCode: String] = [:]
        for key in container.allKeys {
            terms[LanguageCode(key.stringValue)] = try container.decode(String.self, forKey: key)
        }
        self.init(terms: terms)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: LanguageKey.self)
        for (language, term) in terms {
            try container.encode(term, forKey: LanguageKey(language.rawValue))
        }
    }

    struct LanguageKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

/// The user's terminology, filtered at the model rather than at the prompt.
///
/// `FR-GLO-01`. A concept glossary (#59): one row per term, one term per
/// language, so adding a language adds a column rather than rows. Filtering
/// lives here so ``PromptBuilder`` gets only the pair's entries, in one
/// direction -- a prompt carrying both directions of every term is how a
/// small local model gets talked into translating a word it was told to
/// leave alone.
public struct Glossary: Sendable, Equatable, Codable {

    public var concepts: [GlossaryConcept]

    public init(concepts: [GlossaryConcept] = []) {
        self.concepts = concepts.filter { !$0.isEmpty }
    }

    /// The directed entries for this pair, in concept order, from every
    /// concept with a term in both languages.
    public func entries(for pair: LanguagePair) -> [GlossaryEntry] {
        var entries: [GlossaryEntry] = []
        for concept in concepts {
            guard let source = concept.terms[pair.source] else { continue }
            guard let target = concept.terms[pair.target] else { continue }
            entries.append(GlossaryEntry(source: source, target: target, pair: pair))
        }
        return entries
    }

    private enum CodingKeys: String, CodingKey {
        case concepts
        /// Before #59: one directed entry each. Read, never written.
        case entries
    }

    /// `concepts` when present; otherwise the old `entries`, one concept
    /// each, which from then on applies in both directions.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.concepts) {
            self.init(concepts: try container.decode([GlossaryConcept].self, forKey: .concepts))
            return
        }
        var converted: [GlossaryConcept] = []
        if container.contains(.entries) {
            for entry in try container.decode([GlossaryEntry].self, forKey: .entries) {
                var concept = GlossaryConcept()
                concept.set(entry.source, for: entry.pair.source)
                concept.set(entry.target, for: entry.pair.target)
                converted.append(concept)
            }
        }
        self.init(concepts: converted)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(concepts, forKey: .concepts)
    }
}
