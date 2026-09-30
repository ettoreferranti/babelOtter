import Foundation

/// How serious a correction is (`FR-COR-05`).
public enum Severity: String, Sendable, Codable, Equatable {
    case error
    case suggestion
}

/// The closed taxonomy from `FR-COR-03`.
///
/// Closed on purpose: an open string field would let the model invent a new
/// category every few responses, and the tutor's value is that the same mistake
/// is named the same way every time. `other` is the escape hatch.
public enum ErrorCategory: String, Sendable, Codable, CaseIterable, Equatable {
    case grammaticalCase = "case"
    case wordOrder = "word order"
    case gender
    case agreement
    case falseFriend = "false friend"
    case spelling
    case register
    case preposition
    case other
}

/// One itemised change (`FR-COR-02`).
public struct CorrectionError: Sendable, Equatable, Codable {
    public let original: String
    public let corrected: String
    public let category: ErrorCategory
    public let explanationEn: String
    public let severity: Severity

    public init(
        original: String, corrected: String, category: ErrorCategory,
        explanationEn: String, severity: Severity
    ) {
        self.original = original
        self.corrected = corrected
        self.category = category
        self.explanationEn = explanationEn
        self.severity = severity
    }
}

/// The translate and re-pitch contract (spec section 7).
public struct TranslateResponse: Sendable, Equatable, Codable {
    /// Optional: a model that omits its own language guess must not fail the
    /// whole parse, since ``LanguageDetector`` already has an answer.
    public let detectedSource: String?
    /// `FR-PRO-03`'s inference, riding along at no extra round trip.
    public let detectedAudience: String?
    /// Required. Without blocks there is no result to show.
    public let blocks: [String]
}

/// The correct contract (spec section 7).
public struct CorrectResponse: Sendable, Equatable, Codable {
    public let correctedBlocks: [String]
    public let errors: [CorrectionError]
}

// MARK: - Reading a correction's items leniently
//
// Measured 2026-09-30: one reply in three from the default model named two
// categories for one item ("word order|spelling", copying the schema's own
// notation) and padded the list with empty items. Strict decoding threw away
// the whole correction over one malformed item. The items are the model's
// commentary, so they are read leniently; `corrected_blocks`, the text that
// is pasted, is still read strictly (`FR-COR-06`: nothing is guessed there).

extension ErrorCategory {
    /// The first recognised category in a possibly compound, oddly cased or
    /// padded wire value; `other` when there is none.
    static func lenient(_ wire: String) -> ErrorCategory {
        let parts = wire.lowercased().split(whereSeparator: { "|/,;".contains($0) })
        for part in parts {
            let name = part.trimmingCharacters(in: .whitespaces)
            if let category = ErrorCategory(rawValue: name) { return category }
        }
        return .other
    }
}

extension Severity {
    /// Only an explicit "suggestion" is a suggestion. Anything else,
    /// including nothing, is an error: the item describes a change that is
    /// already in `corrected_blocks`, so calling it a suggestion would claim
    /// it was not applied.
    static func lenient(_ wire: String) -> Severity {
        guard wire.trimmingCharacters(in: .whitespaces).lowercased() == "suggestion" else {
            return .error
        }
        return .suggestion
    }
}

extension CorrectionError {
    enum CodingKeys: String, CodingKey {
        case original, corrected, category, explanationEn, severity
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            original: try container.decodeIfPresent(String.self, forKey: .original) ?? "",
            corrected: try container.decodeIfPresent(String.self, forKey: .corrected) ?? "",
            category: ErrorCategory.lenient(
                try container.decodeIfPresent(String.self, forKey: .category) ?? ""),
            explanationEn: try container.decodeIfPresent(String.self, forKey: .explanationEn) ?? "",
            severity: Severity.lenient(
                try container.decodeIfPresent(String.self, forKey: .severity) ?? ""))
    }

    /// An item with neither an original nor a corrected fragment describes
    /// nothing. A deletion has an original; an insertion has a correction.
    var isPadding: Bool {
        original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && corrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension CorrectResponse {
    enum CodingKeys: String, CodingKey {
        case correctedBlocks, errors
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let items = try container.decodeIfPresent([CorrectionError].self, forKey: .errors) ?? []
        self.init(
            correctedBlocks: try container.decode([String].self, forKey: .correctedBlocks),
            errors: items.filter { !$0.isPadding })
    }
}

public struct ExplainNote: Sendable, Equatable, Codable {
    public let phrase: String
    public let explanationEn: String
}

/// The explain contract (spec section 7).
public struct ExplainResponse: Sendable, Equatable, Codable {
    public let summaryEn: String
    public let notes: [ExplainNote]
}

extension JSONDecoder {
    /// Wire keys are snake_case per spec section 7; Swift properties are camelCase.
    ///
    /// Bridged by strategy rather than hand-written `CodingKeys`, so adding a
    /// field cannot be forgotten in a second place.
    static var responseContract: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
