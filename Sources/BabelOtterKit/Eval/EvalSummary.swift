import Foundation

public enum MetricKind: String, Sendable, Codable {
    case rate
    case count
    case seconds
    case score
}

public struct Metric: Sendable, Equatable, Codable {
    public let name: String
    public let value: Double
    public let kind: MetricKind
    public let higherIsBetter: Bool
}

public struct MetricDelta: Sendable, Equatable {
    public let name: String
    public let kind: MetricKind
    public let before: Double
    public let after: Double
    public let higherIsBetter: Bool

    public var change: Double { after - before }
}

/// One model's aggregate over a run, as named metrics in a fixed order.
public protocol EvalSummary: Sendable {
    var model: String { get }
    var metrics: [Metric] { get }
}

extension EvalSummary {
    /// Changes against an earlier summary, metric by metric. A metric the
    /// earlier summary lacks is skipped rather than compared with zero.
    public func delta(from earlier: some EvalSummary) -> [MetricDelta] {
        metrics.compactMap { metric in
            guard let before = earlier.metrics.first(where: { $0.name == metric.name }) else { return nil }
            return MetricDelta(
                name: metric.name, kind: metric.kind, before: before.value, after: metric.value,
                higherIsBetter: metric.higherIsBetter)
        }
    }
}

public struct Latency: Sendable, Equatable, Codable {
    public let median: Double
    public let max: Double

    init(median: Double, max: Double) {
        self.median = median
        self.max = max
    }

    public init(seconds: [Double]) {
        let sorted = seconds.sorted()
        guard let last = sorted.last else {
            self.init(median: 0, max: 0)
            return
        }
        let middle = sorted.count / 2
        let median = sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        self.init(median: median, max: last)
    }
}

/// A ratio that is 0, not NaN, when there is nothing to measure.
func ratio(_ numerator: Double, _ denominator: Double) -> Double {
    guard denominator > 0 else { return 0 }
    return numerator / denominator
}

func failureCounts(_ failures: [EvalFailure?]) -> [String: Int] {
    var counts: [String: Int] = [:]
    for case let failure? in failures {
        counts[failure.rawValue, default: 0] += 1
    }
    return counts
}

/// The count metrics of one model's run, per run: a sum over `runs` repeats
/// divided by `runs`, so a repeated run compares fairly with a single one.
/// The stored fields keep the sums.
public struct CorrectionSummary: EvalSummary, Equatable, Codable {
    public let model: String
    /// How many times every case ran.
    public let runs: Int
    /// Scored cases over all runs.
    public let cases: Int
    public let meanRecall: Double
    public let overCorrectedWords: Int
    public let overCorrectionRate: Double
    public let guardViolations: Int
    public let categoryAccuracy: Double
    public let cleanPassRate: Double
    public let failures: [String: Int]
    public let warnings: Int
    public let latency: Latency

    public init(model: String, scores: [CorrectionScore], seconds: [Double], runs: Int = 1) {
        self.model = model
        self.runs = runs
        cases = scores.count
        let recalls = scores.compactMap(\.recall)
        meanRecall = ratio(recalls.reduce(0, +), Double(recalls.count))
        let answered = scores.filter { $0.failure == nil }
        overCorrectedWords = answered.reduce(0) { $0 + $1.overCorrectedWords }
        overCorrectionRate = ratio(
            Double(overCorrectedWords), Double(answered.reduce(0) { $0 + $1.originalWords }))
        guardViolations = scores.reduce(0) { $0 + $1.guardViolations.count }
        categoryAccuracy = ratio(
            Double(scores.reduce(0) { $0 + $1.categoryMatches }),
            Double(scores.reduce(0) { $0 + $1.foundFixes }))
        let cleanVerdicts = scores.compactMap(\.cleanPassed)
        cleanPassRate = ratio(Double(cleanVerdicts.filter { $0 }.count), Double(cleanVerdicts.count))
        failures = failureCounts(scores.map(\.failure))
        warnings = scores.reduce(0) { $0 + $1.warnings }
        latency = Latency(seconds: seconds)
    }

    public var metrics: [Metric] {
        [
            Metric(name: "recall", value: meanRecall, kind: .rate, higherIsBetter: true),
            Metric(name: "over-correction", value: overCorrectionRate, kind: .rate, higherIsBetter: false),
            Metric(name: "over-corrected words", value: perRun(overCorrectedWords), kind: .count, higherIsBetter: false),
            Metric(name: "guard violations", value: perRun(guardViolations), kind: .count, higherIsBetter: false),
            Metric(name: "category accuracy", value: categoryAccuracy, kind: .rate, higherIsBetter: true),
            Metric(name: "clean pass", value: cleanPassRate, kind: .rate, higherIsBetter: true),
            Metric(name: "failures", value: perRun(failures.values.reduce(0, +)), kind: .count, higherIsBetter: false),
            Metric(name: "warnings", value: perRun(warnings), kind: .count, higherIsBetter: false),
            Metric(name: "latency median", value: latency.median, kind: .seconds, higherIsBetter: false),
            Metric(name: "latency max", value: latency.max, kind: .seconds, higherIsBetter: false),
        ]
    }

    private func perRun(_ total: Int) -> Double { ratio(Double(total), Double(runs)) }

    /// A summary saved before repeats were recorded is one run.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        runs = try container.decodeIfPresent(Int.self, forKey: .runs) ?? 1
        cases = try container.decode(Int.self, forKey: .cases)
        meanRecall = try container.decode(Double.self, forKey: .meanRecall)
        overCorrectedWords = try container.decode(Int.self, forKey: .overCorrectedWords)
        overCorrectionRate = try container.decode(Double.self, forKey: .overCorrectionRate)
        guardViolations = try container.decode(Int.self, forKey: .guardViolations)
        categoryAccuracy = try container.decode(Double.self, forKey: .categoryAccuracy)
        cleanPassRate = try container.decode(Double.self, forKey: .cleanPassRate)
        failures = try container.decode([String: Int].self, forKey: .failures)
        warnings = try container.decode(Int.self, forKey: .warnings)
        latency = try container.decode(Latency.self, forKey: .latency)
    }
}

/// Like `CorrectionSummary`, the failure count is per run.
public struct TranslationSummary: EvalSummary, Equatable, Codable {
    public let model: String
    public let runs: Int
    public let cases: Int
    public let esszettPassRate: Double
    public let termPassRate: Double
    public let structurePassRate: Double
    public let meanChrF: Double
    public let failures: [String: Int]
    public let latency: Latency

    public init(model: String, scores: [TranslationScore], seconds: [Double], runs: Int = 1) {
        self.model = model
        self.runs = runs
        cases = scores.count
        let esszettVerdicts = scores.compactMap(\.esszettAbsent)
        esszettPassRate = ratio(Double(esszettVerdicts.filter { $0 }.count), Double(esszettVerdicts.count))
        termPassRate = ratio(Double(scores.filter(\.termsKept).count), Double(scores.count))
        structurePassRate = ratio(Double(scores.filter(\.structureKept).count), Double(scores.count))
        meanChrF = ratio(scores.reduce(0) { $0 + $1.chrF }, Double(scores.count))
        failures = failureCounts(scores.map(\.failure))
        latency = Latency(seconds: seconds)
    }

    public var metrics: [Metric] {
        [
            Metric(name: "no eszett", value: esszettPassRate, kind: .rate, higherIsBetter: true),
            Metric(name: "terms kept", value: termPassRate, kind: .rate, higherIsBetter: true),
            Metric(name: "structure kept", value: structurePassRate, kind: .rate, higherIsBetter: true),
            Metric(name: "chrF", value: meanChrF, kind: .score, higherIsBetter: true),
            Metric(name: "failures", value: perRun(failures.values.reduce(0, +)), kind: .count, higherIsBetter: false),
            Metric(name: "latency median", value: latency.median, kind: .seconds, higherIsBetter: false),
            Metric(name: "latency max", value: latency.max, kind: .seconds, higherIsBetter: false),
        ]
    }

    private func perRun(_ total: Int) -> Double { ratio(Double(total), Double(runs)) }

    /// A summary saved before repeats were recorded is one run.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        runs = try container.decodeIfPresent(Int.self, forKey: .runs) ?? 1
        cases = try container.decode(Int.self, forKey: .cases)
        esszettPassRate = try container.decode(Double.self, forKey: .esszettPassRate)
        termPassRate = try container.decode(Double.self, forKey: .termPassRate)
        structurePassRate = try container.decode(Double.self, forKey: .structurePassRate)
        meanChrF = try container.decode(Double.self, forKey: .meanChrF)
        failures = try container.decode([String: Int].self, forKey: .failures)
        latency = try container.decode(Latency.self, forKey: .latency)
    }
}
