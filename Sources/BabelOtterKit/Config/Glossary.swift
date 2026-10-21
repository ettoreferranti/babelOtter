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
    /// Two spellings of one code ("de-CH", "de-ch") keep the first in
    /// sorted order, the same on every launch.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: LanguageKey.self)
        self.init()
        let keys = container.allKeys.sorted { $0.stringValue < $1.stringValue }
        for key in keys {
            let term = try container.decode(String.self, forKey: key)
            let language = LanguageCode(key.stringValue)
            if terms[language] == nil { set(term, for: language) }
        }
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
    /// concept with a term in both languages. A source term two rows give
    /// (possible by hand, never from the settings window) keeps the first:
    /// two renderings for one term would leave the model to choose.
    public func entries(for pair: LanguagePair) -> [GlossaryEntry] {
        var entries: [GlossaryEntry] = []
        var seen: Set<String> = []
        for concept in concepts {
            guard let source = concept.terms[pair.source] else { continue }
            guard let target = concept.terms[pair.target] else { continue }
            if !seen.insert(source.lowercased()).inserted { continue }
            entries.append(GlossaryEntry(source: source, target: target, pair: pair))
        }
        return entries
    }

    private enum CodingKeys: String, CodingKey {
        case concepts
        /// Before #59: one directed entry each. Read, never written.
        case entries
    }

    /// `concepts` when present; otherwise the old `entries`, which from then
    /// on apply in both directions. The old format needed one entry per
    /// direction, so entries sharing a term are merged into one concept;
    /// where they disagree ("Modul" into English as "module", then as
    /// "course unit"), the first wins.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.concepts) {
            self.init(concepts: try container.decode([GlossaryConcept].self, forKey: .concepts))
            return
        }
        var converted: [GlossaryConcept] = []
        if container.contains(.entries) {
            for entry in try container.decode([GlossaryEntry].self, forKey: .entries) {
                Self.merge(entry, into: &converted)
            }
        }
        self.init(concepts: converted)
    }

    private static func merge(_ entry: GlossaryEntry, into concepts: inout [GlossaryConcept]) {
        // Within one language: nothing to translate, nothing to keep.
        if entry.pair.source == entry.pair.target { return }
        var incoming = GlossaryConcept()
        incoming.set(entry.source, for: entry.pair.source)
        incoming.set(entry.target, for: entry.pair.target)
        for index in concepts.indices {
            if shareATerm(concepts[index], incoming) {
                for (language, term) in incoming.terms {
                    if concepts[index].terms[language] == nil { concepts[index].set(term, for: language) }
                }
                return
            }
        }
        concepts.append(incoming)
    }

    /// The same term for the same language, ignoring case.
    private static func shareATerm(_ lhs: GlossaryConcept, _ rhs: GlossaryConcept) -> Bool {
        for (language, term) in rhs.terms {
            if lhs.terms[language]?.lowercased() == term.lowercased() { return true }
        }
        return false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(concepts, forKey: .concepts)
    }
}
