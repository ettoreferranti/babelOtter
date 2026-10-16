import BabelOtterKit
import SwiftUI

/// A finished explanation: the summary, then one row per note (#65).
struct ExplanationContent: View {
    let explanation: ExplanationResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(explanation.summary).textSelection(.enabled)
                if !explanation.notes.isEmpty {
                    Divider()
                    ForEach(Array(explanation.notes.enumerated()), id: \.offset) { _, note in
                        ExplanationNoteRow(note: note)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 420)
    }
}

/// One phrase from the text, and what it means.
struct ExplanationNoteRow: View {
    let note: ExplainNote

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.phrase).font(.callout.bold()).textSelection(.enabled)
            Text(note.explanationEn).font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
