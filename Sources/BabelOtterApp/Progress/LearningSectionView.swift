import BabelOtterKit
import SwiftUI

/// The top of the Progress window (#136): this week against the goal, the
/// streak, the milestones earned and the next one, and Reset.
struct LearningSectionView: View {

    let model: ProgressModel
    @State private var confirmsReset = false

    var body: some View {
        let log = model.learning.log
        let week = model.learning.week()
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("This week").font(.headline)
                dots(week)
                Text("\(week.days) of \(week.goal) learning days").foregroundStyle(.secondary)
                Spacer()
                if week.streak >= 2 {
                    Text("\(week.streak) weeks in a row").foregroundStyle(.green)
                } else if week.isMet {
                    Text("Goal met").foregroundStyle(.green)
                }
            }
            if log.isEmpty {
                Text("Correct a text you wrote in another language, or Explain one, to start your week.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !log.earned.isEmpty { milestones(log) }
            HStack {
                if let next = LearningRules.next(log) {
                    Text("Next: \(model.title(next.milestone)) (\(next.current.formatted()) so far)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset\u{2026}") { confirmsReset = true }
                    .buttonStyle(.link).font(.caption)
                    .disabled(log.isEmpty)
            }
        }
        .alert("Reset the learning log?", isPresented: $confirmsReset) {
            Button("Reset", role: .destructive) { model.learning.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The learning days, the totals and the milestones are cleared. History is not touched.")
        }
    }

    /// One dot per day of the goal, filled for each learning day.
    private func dots(_ week: LearningWeek) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<week.goal, id: \.self) { index in
                Image(systemName: index < week.days ? "circle.fill" : "circle")
                    .font(.caption2)
                    .foregroundStyle(index < week.days ? Color.green : Color.secondary)
            }
        }
        .accessibilityHidden(true)
    }

    private func milestones(_ log: LearningLog) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(log.earned.enumerated()), id: \.offset) { _, entry in
                    Text(model.title(entry.milestone))
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .help(Self.earnedOn(entry.day))
                }
            }
        }
    }

    private static func earnedOn(_ day: LearningDay) -> String {
        guard let date = day.date(calendar: .current) else { return "Earned" }
        return "Earned on " + date.formatted(date: .abbreviated, time: .omitted)
    }
}
