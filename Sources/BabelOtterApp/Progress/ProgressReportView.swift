import BabelOtterKit
import Charts
import SwiftUI

/// Recurring mistakes over time (#78): a summary, then one row per error
/// category with its rate, trend, weekly chart and examples.
struct ProgressReportView: View {

    @Bindable var model: ProgressModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls.padding(12)
            if let notice = model.notice {
                Label(notice, systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.bottom, 10)
            }
            Divider()
            if model.isEmpty {
                empty
            } else if let report = model.report {
                content(report)
            }
        }
        .frame(minWidth: 560, minHeight: 360)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if !model.languages.isEmpty {
                Picker("Language", selection: Binding(
                    get: { model.language },
                    set: { model.choose($0) }
                )) {
                    ForEach(model.languages, id: \.self) { code in
                        Text(model.displayName(code)).tag(LanguageCode?.some(code))
                    }
                }
                .fixedSize()
            }
            Picker("Period", selection: $model.period) {
                ForEach(ProgressPeriod.allCases, id: \.self) { period in
                    Text(period.title).tag(period)
                }
            }
            .fixedSize()
            Spacer()
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No corrections yet").font(.title3)
            Text("Correct a few texts and your patterns appear here. Corrections from before this version are not counted.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func content(_ report: ProgressReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary(report)
                if report.rows.isEmpty {
                    Text(report.words == 0
                        ? "Nothing corrected in this period."
                        : "No errors in this period.")
                        .foregroundStyle(.secondary)
                }
                ForEach(report.rows, id: \.category) { row in
                    CategoryRow(row: row)
                    Divider()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summary(_ report: ProgressReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("\(report.words.formatted()) words corrected")
                if let rate = report.rate {
                    Text("\u{00B7} \(ProgressFormat.rate(rate)) errors per 100 words")
                }
                if let trend = report.trend { TrendText(trend: trend) }
            }
            .font(.headline)
            if !report.isReliable, report.words > 0 {
                Text("Not enough text yet for a reliable rate: \(ProgressReport.minimumWords) words or more.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// One category: its numbers, its chart and its examples.
private struct CategoryRow: View {
    let row: ProgressRow
    @State private var showsAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Text(row.category.displayName).font(.headline).frame(width: 110, alignment: .leading)
                Text("\(row.count)").monospacedDigit()
                Text("\u{00B7} \(ProgressFormat.rate(row.rate)) per 100 words")
                    .foregroundStyle(.secondary)
                if let trend = row.trend { TrendText(trend: trend) }
                Spacer()
                chart.frame(width: 120, height: 28)
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, mistake in
                ExampleRow(mistake: mistake)
            }
            if row.examples.count > Self.firstExamples {
                Button(showsAll ? "Show fewer" : "Show more (\(row.examples.count))") { showsAll.toggle() }
                    .buttonStyle(.link).font(.caption)
            }
        }
    }

    private static let firstExamples = 3

    private var shown: [Mistake] {
        if showsAll { return row.examples }
        return Array(row.examples.prefix(Self.firstExamples))
    }

    private var chart: some View {
        // By bucket index on a fixed domain, so every row's chart spans the
        // whole period and the rows compare.
        Chart {
            ForEach(Array(row.series.enumerated()), id: \.offset) { index, point in
                if let rate = point.rate {
                    BarMark(x: .value("Part", index), y: .value("Rate", rate))
                }
            }
        }
        .chartXScale(domain: -0.5...(Double(row.series.count) - 0.5))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .help("Errors per 100 words, by day or week")
    }
}

private struct ExampleRow: View {
    let mistake: Mistake

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\u{201C}\(mistake.original.value)\u{201D} \u{2192} \u{201C}\(mistake.corrected.value)\u{201D}")
                .font(.callout).textSelection(.enabled)
            Text(mistake.explanation.value).font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.leading, 120)
    }
}

private struct TrendText: View {
    let trend: ProgressTrend

    var body: some View {
        switch trend {
        case .down(let from):
            Text("\u{2193} from \(ProgressFormat.rate(from))").foregroundStyle(.green)
        case .up(let from):
            Text("\u{2191} from \(ProgressFormat.rate(from))").foregroundStyle(.orange)
        case .steady:
            Text("\u{2192} steady").foregroundStyle(.secondary)
        }
    }
}

enum ProgressFormat {
    static func rate(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
