import Foundation

/// Why a case produced no result. Recall is then 0, and the kind is
/// reported on its own so a parse problem is never mistaken for a weak model.
public enum EvalFailure: String, Sendable, Equatable, Codable {
    case unreadableReply
    case structureLost
    /// The case's text was not taken for its language (#81; was notGerman).
    case wrongLanguage
    case emptyResponse
    case timeout
    /// No response at all: nothing listening, or a timeout before the
    /// response headers (the transport reports both alike).
    case unreachable
    case other

    /// Reads the name used before #81 too, so earlier reports still load.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == "notGerman" {
            self = .wrongLanguage
            return
        }
        guard let known = EvalFailure(rawValue: raw) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath, debugDescription: "unknown failure \(raw)"))
        }
        self = known
    }

    public init(_ error: any Error) {
        if let failure = error as? CorrectionFailure {
            self = Self.kind(of: failure)
        } else if let failure = error as? TranslationError, failure == .emptyResponse {
            self = .emptyResponse
        } else if let failure = error as? URLError, failure.code == .timedOut {
            self = .timeout
        } else if case .unreachable? = error as? OllamaTransportError {
            self = .unreachable
        } else {
            self = .other
        }
    }

    private static func kind(of failure: CorrectionFailure) -> EvalFailure {
        switch failure {
        case .unreadableReply: return .unreadableReply
        case .structureLost: return .structureLost
        case .notEnabled, .needsLanguage: return .wrongLanguage
        case .emptyResponse: return .emptyResponse
        }
    }
}
