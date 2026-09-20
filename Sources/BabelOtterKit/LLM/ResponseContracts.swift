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
