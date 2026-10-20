import BabelOtterKit
import SwiftUI

/// The History window: search and list on the left, the selected record on
/// the right (#68, `FR-HIS-02`).
struct HistoryView: View {

    @ObservedObject var model: HistoryWindowModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                TextField("Search source and result", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .padding(8)
                if case .reading(let reason) = model.problem {
                    Text("Could not read the history - \(reason)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                }
                list
            }
            .frame(minWidth: 260, idealWidth: 320)
            detail
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: model.searchFocusRequests) { searchFocused = true }
    }

    @ViewBuilder private var list: some View {
        if case .unavailable(let reason) = model.problem {
            placeholder("History is not saved - \(reason)")
        } else if model.records.isEmpty {
            if let term = model.term {
                placeholder("No records contain \"\(term)\".")
            } else {
                placeholder("Nothing recorded yet.")
            }
        } else {
            List(selection: $model.selection) {
                ForEach(model.records, id: \.id) { record in
                    HistoryRowView(row: model.row(record), date: record.date)
                        .tag(record.id ?? 0)
                        .onAppear {
                            if record.id == model.records.last?.id, model.hasMore {
                                model.loadMore()
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let record = model.selectedRecord {
            HistoryDetailView(record: record, row: model.row(record))
                .id(record.id)
        } else {
            placeholder("Select a record")
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HistoryRowView: View {
    let row: HistoryRow
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(row.title) \u{00B7} \(row.languages)")
                    .lineLimit(1)
                Spacer()
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(row.excerpt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

private struct HistoryDetailView: View {
    let record: HistoryRecord
    let row: HistoryRow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextSection(title: "Source", text: record.source.value)
            TextSection(title: "Result", text: record.result.value)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                if let audience = row.audience { detailLine("Audience", audience) }
                if let application = row.application { detailLine("App", application) }
                detailLine("Model", record.model)
                detailLine("Date", record.date.formatted(date: .long, time: .standard))
            }
            .font(.caption)
        }
        .padding(12)
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}

/// A heading with a Copy button over selectable, scrolling text.
private struct TextSection: View {
    static let copiedPause = Duration.seconds(1.2)

    let title: String
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button(copied ? "Copied" : "Copy") { copy() }
            }
            ScrollView {
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(6)
            }
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func copy() {
        SystemPasteboard().write(text, concealed: false)
        copied = true
        Task {
            try? await Task.sleep(for: Self.copiedPause)
            copied = false
        }
    }
}
