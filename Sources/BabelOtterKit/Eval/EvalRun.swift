import Foundation

/// One case, one model, one repetition, as saved.
public struct CaseRecord: Sendable, Equatable, Codable {
    public let model: String
    public let caseID: String
    public let run: Int
    public let seconds: Double
    /// The corrected or translated text. Golden-set text is synthetic, so
    /// saving it is safe (NFR-P8); results are git-ignored all the same.
    public let output: String?
    public let failureDetail: String?
    public let correction: CorrectionScore?
    public let translation: TranslationScore?

    public init(
        model: String, caseID: String, run: Int, seconds: Double, output: String?,
        failureDetail: String?, correction: CorrectionScore?, translation: TranslationScore?
    ) {
        self.model = model
        self.caseID = caseID
        self.run = run
        self.seconds = seconds
        self.output = output
        self.failureDetail = failureDetail
        self.correction = correction
        self.translation = translation
    }
}

/// A whole run, saved to `evals/results/` and read back by `--compare`.
public struct EvalRun: Sendable, Equatable, Codable {
    public let startedAt: Date
    public let commit: String
    /// How many times every case ran (`--repeat`).
    public let repeatCount: Int
    public let correction: [CorrectionSummary]
    public let translation: [TranslationSummary]
    public let records: [CaseRecord]

    public init(
        startedAt: Date, commit: String, repeatCount: Int = 1, correction: [CorrectionSummary],
        translation: [TranslationSummary], records: [CaseRecord]
    ) {
        self.startedAt = startedAt
        self.commit = commit
        self.repeatCount = repeatCount
        self.correction = correction
        self.translation = translation
        self.records = records
    }

    /// A run saved before repeats were recorded is one run.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        commit = try container.decode(String.self, forKey: .commit)
        repeatCount = try container.decodeIfPresent(Int.self, forKey: .repeatCount) ?? 1
        correction = try container.decode([CorrectionSummary].self, forKey: .correction)
        translation = try container.decode([TranslationSummary].self, forKey: .translation)
        records = try container.decode([CaseRecord].self, forKey: .records)
    }

    /// Whether no case produced a result at all, as when the daemon went
    /// away: the CLI then exits with a failure status.
    public var everyCaseFailed: Bool {
        !records.isEmpty && records.allSatisfy { ($0.correction?.failure ?? $0.translation?.failure) != nil }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> EvalRun {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EvalRun.self, from: data)
    }

    /// `yyyy-MM-dd-HHmmss-<commit>.json`.
    public static func fileName(startedAt: Date, commit: String, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "\(formatter.string(from: startedAt))-\(commit).json"
    }

    /// This run's summaries rebuilt from its records, over only the
    /// (model, case) pairs of `current`, so `--compare` compares like with
    /// like when the earlier run covered other cases. A model this run has
    /// no record of gets no summary.
    public func comparable(to current: [CaseRecord]) -> EvalBaseline {
        var models: [String] = []
        for record in current where !models.contains(record.model) {
            models.append(record.model)
        }
        var correction: [CorrectionSummary] = []
        var translation: [TranslationSummary] = []
        var missing: [String: [String]] = [:]
        for model in models {
            let wanted = Set(current.filter { $0.model == model }.map(\.caseID))
            let earlier = records.filter { $0.model == model && wanted.contains($0.caseID) }
            let corrections = earlier.filter { $0.correction != nil }
            if !corrections.isEmpty {
                correction.append(CorrectionSummary(
                    model: model, scores: corrections.compactMap(\.correction),
                    seconds: corrections.map(\.seconds), runs: repeatCount))
            }
            let translations = earlier.filter { $0.translation != nil }
            if !translations.isEmpty {
                translation.append(TranslationSummary(
                    model: model, scores: translations.compactMap(\.translation),
                    seconds: translations.map(\.seconds), runs: repeatCount))
            }
            let known = Set(earlier.map(\.caseID))
            var absent: [String] = []
            for record in current where record.model == model && !known.contains(record.caseID)
                && !absent.contains(record.caseID) {
                absent.append(record.caseID)
            }
            if !absent.isEmpty { missing[model] = absent }
        }
        return EvalBaseline(correction: correction, translation: translation, missing: missing)
    }
}

/// An earlier run made comparable with the current one.
public struct EvalBaseline: Sendable, Equatable {
    public let correction: [CorrectionSummary]
    public let translation: [TranslationSummary]
    /// Per model, the current run's case ids the earlier run has no record
    /// of, in the current run's order. Models with none are left out.
    public let missing: [String: [String]]
}
