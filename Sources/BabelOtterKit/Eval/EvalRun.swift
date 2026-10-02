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
    public let correction: [CorrectionSummary]
    public let translation: [TranslationSummary]
    public let records: [CaseRecord]

    public init(
        startedAt: Date, commit: String, correction: [CorrectionSummary],
        translation: [TranslationSummary], records: [CaseRecord]
    ) {
        self.startedAt = startedAt
        self.commit = commit
        self.correction = correction
        self.translation = translation
        self.records = records
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

    /// `yyyy-MM-dd-HHmm-<commit>.json`.
    public static func fileName(startedAt: Date, commit: String, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "\(formatter.string(from: startedAt))-\(commit).json"
    }
}
