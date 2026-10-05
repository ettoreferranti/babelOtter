import Foundation

public enum EvalSelection: Sendable, Equatable {
    case everything
    case correctionOnly
    case translationOnly
    case cases([String])
}

public struct EvalArgumentError: Error, Equatable, CustomStringConvertible {
    public let message: String

    init(message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// `babelotter-eval [--models a,b] [--only correct|translate|<id>,...]
/// [--repeat N] [--compare <file>]`, parsed (spec 2026-09-30, section 5).
public struct EvalArguments: Sendable, Equatable {
    public var models: [String]?
    public var selection: EvalSelection
    public var repeatCount: Int
    public var compare: String?

    static let flags = ["--models", "--only", "--repeat", "--compare"]

    public static func parse(_ arguments: [String]) throws -> EvalArguments {
        var parsed = EvalArguments(models: nil, selection: .everything, repeatCount: 1, compare: nil)
        var seen: Set<String> = []
        var remaining = arguments[...]
        while let flag = remaining.popFirst() {
            guard flags.contains(flag) else { throw EvalArgumentError(message: "unknown option \(flag)") }
            guard seen.insert(flag).inserted else { throw EvalArgumentError(message: "\(flag) given twice") }
            guard let value = remaining.popFirst(), !value.hasPrefix("--") else {
                throw EvalArgumentError(message: "\(flag) needs a value")
            }
            try parsed.apply(flag, value)
        }
        return parsed
    }

    private mutating func apply(_ flag: String, _ value: String) throws {
        switch flag {
        case "--models":
            models = try Self.list(value, flag)
        case "--only":
            selection = try Self.selection(value)
        case "--repeat":
            guard let count = Int(value), count >= 1 else {
                throw EvalArgumentError(message: "--repeat needs a whole number of at least 1, not \(value)")
            }
            repeatCount = count
        default:
            compare = value
        }
    }

    private static func selection(_ value: String) throws -> EvalSelection {
        switch value {
        case "correct": return .correctionOnly
        case "translate": return .translationOnly
        default: return .cases(try list(value, "--only"))
        }
    }

    private static func list(_ value: String, _ flag: String) throws -> [String] {
        let items = value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !items.isEmpty else { throw EvalArgumentError(message: "\(flag) needs at least one name") }
        return items
    }

    public func cases(from golden: GoldenSet) throws -> (correction: [CorrectionCase], translation: [TranslationCase]) {
        switch selection {
        case .everything:
            return (golden.correction, golden.translation)
        case .correctionOnly:
            return (golden.correction, [])
        case .translationOnly:
            return ([], golden.translation)
        case .cases(let ids):
            let known = Set(golden.correction.map(\.id) + golden.translation.map(\.id))
            let unknown = ids.filter { !known.contains($0) }
            guard unknown.isEmpty else {
                throw EvalArgumentError(message: "no case named \(unknown.joined(separator: ", "))")
            }
            return (golden.correction.filter { ids.contains($0.id) }, golden.translation.filter { ids.contains($0.id) })
        }
    }
}
