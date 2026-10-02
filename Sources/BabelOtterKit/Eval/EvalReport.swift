import Foundation

/// The evaluation report as text: the comparison table and the misses.
public enum EvalReport {

    public static func table<S: EvalSummary>(_ title: String, _ summaries: [S], baseline: [S]) -> String {
        guard let first = summaries.first else { return "" }
        var rows = [["metric"] + summaries.map(\.model)]
        for metric in first.metrics {
            var row = [metric.name]
            for summary in summaries {
                row.append(cell(metric.name, of: summary, baseline: baseline))
            }
            rows.append(row)
        }
        return ([title] + render(rows)).joined(separator: "\n")
    }

    private static func cell<S: EvalSummary>(_ name: String, of summary: S, baseline: [S]) -> String {
        guard let metric = summary.metrics.first(where: { $0.name == name }) else { return "" }
        let value = format(metric.value, metric.kind)
        guard let earlier = baseline.first(where: { $0.model == summary.model }),
              let delta = summary.delta(from: earlier).first(where: { $0.name == name })
        else { return value }
        return "\(value) (\(signedChange(delta.change, delta.kind)))"
    }

    private static func render(_ rows: [[String]]) -> [String] {
        let columns = rows.map(\.count).max() ?? 0
        let widths = (0..<columns).map { column in
            rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0
        }
        return rows.map { row in
            row.enumerated()
                .map { $1.padding(toLength: widths[$0], withPad: " ", startingAt: 0) }
                .joined(separator: "  ")
                .replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        }
    }

    public static func format(_ value: Double, _ kind: MetricKind) -> String {
        switch kind {
        case .rate: return String(format: "%.1f%%", value * 100)
        case .count: return String(Int(value.rounded()))
        case .seconds: return String(format: "%.1fs", value)
        case .score: return String(format: "%.1f", value)
        }
    }

    public static func signedChange(_ change: Double, _ kind: MetricKind) -> String {
        switch kind {
        case .rate: return String(format: "%+.1fpp", change * 100)
        case .count:
            let whole = Int(change.rounded())
            return whole < 0 ? String(whole) : "+\(whole)"
        case .seconds: return String(format: "%+.1fs", change)
        case .score: return String(format: "%+.1f", change)
        }
    }

    public static func correctionMisses(
        model: String, testCase: CorrectionCase, score: CorrectionScore
    ) -> [String] {
        let prefix = "\(model)  \(testCase.id): "
        if let failure = score.failure { return [prefix + "failed (\(failure.rawValue))"] }
        var lines = score.missedFixes.map { wrong in
            let expected = testCase.fixes.first { $0.wrong == wrong }?.right.first ?? ""
            return prefix + "missed \"\(wrong)\" (expected \"\(expected)\")"
        }
        lines += score.guardViolations.map { prefix + "must not contain \"\($0)\"" }
        if score.cleanPassed == false { lines.append(prefix + "the clean text was changed or flagged") }
        return lines
    }

    public static func translationMisses(
        model: String, testCase: TranslationCase, score: TranslationScore
    ) -> [String] {
        let prefix = "\(model)  \(testCase.id): "
        if let failure = score.failure { return [prefix + "failed (\(failure.rawValue))"] }
        var lines: [String] = []
        if score.esszettAbsent == false { lines.append(prefix + "contains an eszett") }
        lines += score.missingTerms.map { prefix + "term \"\($0)\" not kept" }
        if score.sentinelDebris { lines.append(prefix + "a placeholder was left in the output") }
        if !score.structureKept { lines.append(prefix + "structure changed") }
        return lines
    }
}
