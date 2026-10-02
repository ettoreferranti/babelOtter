import Foundation

/// Why a case produced no result. Recall is then 0, and the kind is
/// reported on its own so a parse problem is never mistaken for a weak model.
public enum EvalFailure: String, Sendable, Equatable, Codable, CaseIterable {
    case unreadableReply
    case structureLost
    case notGerman
    case emptyResponse
    case timeout
    case other

    public init(_ error: any Error) {
        if let failure = error as? CorrectionFailure {
            self = Self.kind(of: failure)
        } else if let failure = error as? TranslationError, failure == .emptyResponse {
            self = .emptyResponse
        } else if let failure = error as? URLError, failure.code == .timedOut {
            self = .timeout
        } else {
            self = .other
        }
    }

    private static func kind(of failure: CorrectionFailure) -> EvalFailure {
        switch failure {
        case .unreadableReply: return .unreadableReply
        case .structureLost: return .structureLost
        case .notGerman: return .notGerman
        case .emptyResponse: return .emptyResponse
        }
    }
}
