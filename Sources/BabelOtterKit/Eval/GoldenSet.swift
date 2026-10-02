import Foundation

/// One error a correction case expects the model to fix.
public struct ExpectedFix: Sendable, Equatable {
    /// As the case's text has it; matched on whole words.
    public let wrong: String
    /// Acceptable corrections; any one of them counts.
    public let right: [String]
    public let category: ErrorCategory
}

public struct CorrectionCase: Sendable, Equatable {
    public let id: String
    public let text: String
    public let profileID: String
    /// Do-not-translate terms, added to the configuration for this case.
    public let terms: [String]
    public let fixes: [ExpectedFix]
    /// Strings that must not appear in the output: meaning guards.
    public let mustNot: [String]
    /// An error-free text, for measuring over-correction.
    public let clean: Bool
}

public enum TranslationDirection: String, Sendable, Equatable, CaseIterable {
    case englishToSwissGerman = "en-de-ch"
    case swissGermanToEnglish = "de-ch-en"

    public var direction: Direction {
        switch self {
        case .englishToSwissGerman:
            return Direction(source: LanguageConfig.english.code, target: LanguageConfig.swissGerman.code)
        case .swissGermanToEnglish:
            return Direction(source: LanguageConfig.swissGerman.code, target: LanguageConfig.english.code)
        }
    }

    /// Whether the target is the German locale, whose output must carry no eszett.
    public var targetIsGerman: Bool {
        switch self {
        case .englishToSwissGerman: return true
        case .swissGermanToEnglish: return false
        }
    }
}

public struct TranslationCase: Sendable, Equatable {
    public let id: String
    public let text: String
    public let direction: TranslationDirection
    public let profileID: String
    public let terms: [String]
    public let reference: String
}

public struct GoldenSetError: Error, Equatable, CustomStringConvertible {
    public let file: String
    public let caseID: String?
    public let field: String
    public let reason: String

    public var description: String {
        let place = caseID.map { "case \"\($0)\", " } ?? ""
        return "\(file): \(place)\(field): \(reason)"
    }
}

/// The evaluation harness's fixed cases (spec 2026-09-30, section 3).
///
/// Loading validates every case, because a case that can never pass -- or
/// never fail -- measures nothing and would quietly skew every score. The
/// first problem found is thrown, naming the file, the case and the field.
public struct GoldenSet: Sendable, Equatable {
    public let correction: [CorrectionCase]
    public let translation: [TranslationCase]

    static let correctionFile = "correction.json"
    static let translationFile = "translation.json"
    static let knownProfiles = Set(AudienceProfile.shippedDefaults.map(\.id))

    public static func load(correction: Data, translation: Data) throws -> GoldenSet {
        let rawCorrection = try decode([RawCorrectionCase].self, correction, file: correctionFile)
        let rawTranslation = try decode([RawTranslationCase].self, translation, file: translationFile)
        var ids: Set<String> = []
        var corrections: [CorrectionCase] = []
        for raw in rawCorrection {
            corrections.append(try validated(raw, ids: &ids))
        }
        var translations: [TranslationCase] = []
        for raw in rawTranslation {
            translations.append(try validated(raw, ids: &ids))
        }
        return GoldenSet(correction: corrections, translation: translations)
    }

    // MARK: - Decoding

    private struct RawFix: Decodable {
        let wrong: String
        let right: [String]
        let category: String
    }

    private struct RawCorrectionCase: Decodable {
        let id: String
        let text: String
        let profile: String?
        let terms: [String]?
        let fixes: [RawFix]
        let mustNot: [String]?
        let clean: Bool?
    }

    private struct RawTranslationCase: Decodable {
        let id: String
        let text: String
        let direction: String
        let profile: String?
        let terms: [String]?
        let reference: String
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data, file: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw GoldenSetError(file: file, caseID: nil, field: "json", reason: String(describing: error))
        }
    }

    // MARK: - Validation

    private typealias Failure = (_ field: String, _ reason: String) -> GoldenSetError

    private static func validated(_ raw: RawCorrectionCase, ids: inout Set<String>) throws -> CorrectionCase {
        let fail: Failure = { GoldenSetError(file: correctionFile, caseID: raw.id, field: $0, reason: $1) }
        try checkID(raw.id, ids: &ids, fail: fail)
        guard !raw.text.isEmpty else { throw fail("text", "is empty") }
        let profile = try checkedProfile(raw.profile, fail: fail)
        let terms = raw.terms ?? []
        try checkTerms(terms, occurIn: raw.text, fail: fail)
        var fixes: [ExpectedFix] = []
        for (index, fix) in raw.fixes.enumerated() {
            fixes.append(try validated(fix, field: "fixes[\(index)]", text: raw.text, fail: fail))
        }
        let mustNot = raw.mustNot ?? []
        for (index, phrase) in mustNot.enumerated() {
            guard !phrase.isEmpty else { throw fail("mustNot[\(index)]", "is empty") }
            guard !raw.text.contains(phrase) else {
                throw fail("mustNot[\(index)]", "\"\(phrase)\" is already in the text, so the guard can never pass")
            }
        }
        let clean = raw.clean ?? false
        if clean && !fixes.isEmpty { throw fail("fixes", "a clean case lists no fixes") }
        if !clean && fixes.isEmpty && mustNot.isEmpty {
            throw fail("fixes", "a case that is not clean needs at least one fix or mustNot guard")
        }
        return CorrectionCase(
            id: raw.id, text: raw.text, profileID: profile, terms: terms, fixes: fixes,
            mustNot: mustNot, clean: clean)
    }

    private static func validated(
        _ raw: RawFix, field: String, text: String, fail: Failure
    ) throws -> ExpectedFix {
        guard TextSearch.contains(raw.wrong, in: text) else {
            throw fail(field + ".wrong", "\"\(raw.wrong)\" does not occur in the text as whole words")
        }
        guard !raw.right.isEmpty else { throw fail(field + ".right", "lists no alternative") }
        for (index, alternative) in raw.right.enumerated() {
            guard !alternative.isEmpty else { throw fail("\(field).right[\(index)]", "is empty") }
            guard !TextSearch.contains(raw.wrong, in: alternative) else {
                throw fail("\(field).right[\(index)]", "contains \"\(raw.wrong)\", so the fix could never be found")
            }
        }
        guard let category = ErrorCategory(rawValue: raw.category) else {
            let known = ErrorCategory.allCases.map(\.rawValue).joined(separator: ", ")
            throw fail(field + ".category", "\"\(raw.category)\" is not one of: \(known)")
        }
        return ExpectedFix(wrong: raw.wrong, right: raw.right, category: category)
    }

    private static func validated(_ raw: RawTranslationCase, ids: inout Set<String>) throws -> TranslationCase {
        let fail: Failure = { GoldenSetError(file: translationFile, caseID: raw.id, field: $0, reason: $1) }
        try checkID(raw.id, ids: &ids, fail: fail)
        guard !raw.text.isEmpty else { throw fail("text", "is empty") }
        guard let direction = TranslationDirection(rawValue: raw.direction) else {
            let known = TranslationDirection.allCases.map(\.rawValue).joined(separator: ", ")
            throw fail("direction", "\"\(raw.direction)\" is not one of: \(known)")
        }
        let profile = try checkedProfile(raw.profile, fail: fail)
        guard !raw.reference.isEmpty else { throw fail("reference", "is empty") }
        let terms = raw.terms ?? []
        try checkTerms(terms, occurIn: raw.text, fail: fail)
        try checkTerms(terms, occurIn: raw.reference, fail: fail)
        return TranslationCase(
            id: raw.id, text: raw.text, direction: direction, profileID: profile, terms: terms,
            reference: raw.reference)
    }

    private static func checkID(_ id: String, ids: inout Set<String>, fail: Failure) throws {
        guard !id.isEmpty else { throw fail("id", "is empty") }
        guard ids.insert(id).inserted else { throw fail("id", "is used by another case") }
    }

    private static func checkedProfile(_ profile: String?, fail: Failure) throws -> String {
        let id = profile ?? AudienceProfile.colleagues.id
        guard knownProfiles.contains(id) else {
            let known = knownProfiles.sorted().joined(separator: ", ")
            throw fail("profile", "\"\(id)\" is not a shipped profile: \(known)")
        }
        return id
    }

    private static func checkTerms(_ terms: [String], occurIn text: String, fail: Failure) throws {
        for (index, term) in terms.enumerated() {
            guard !term.isEmpty, text.contains(term) else {
                throw fail("terms[\(index)]", "\"\(term)\" does not occur in the text it protects")
            }
        }
    }
}
