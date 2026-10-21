import BabelOtterKit
import SwiftUI

/// The concept glossary and the do-not-translate list (#59). A grid rather
/// than a `Table`: a column per language needs `TableColumnForEach`, which
/// is macOS 14.4, and lingoSwen supports 14.0. Closures rather than method
/// references throughout (PR #108).
struct GlossarySettingsView: View {

    @ObservedObject var model: SettingsModel
    /// An empty row at the end of a table, saved by its first term.
    @State private var addingConcept = false
    @State private var addingTerm = false

    private var languages: [LanguageConfig] { model.configuration.languages }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FileProblemBanner(model: model).padding([.horizontal, .top])
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    terms
                    doNotTranslate
                }
                .padding()
            }
            .disabled(model.isReadOnly)
        }
        .onChange(of: model.configuration.glossary) { addingConcept = false }
        .onChange(of: model.configuration.doNotTranslate) { addingTerm = false }
    }

    // MARK: - Terms

    private var terms: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Terms").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                GridRow {
                    ForEach(languages, id: \.code) { language in
                        Text(language.displayName).font(.caption).foregroundStyle(.secondary)
                    }
                    Color.clear.frame(width: 20, height: 1)
                }
                // One list, the new row last: when its first term saves it, it
                // keeps its place and focus rather than being replaced.
                ForEach(0..<conceptRows, id: \.self) { index in
                    conceptRow(index, concept(at: index))
                }
            }
            HStack {
                Button { addingConcept = true } label: { Image(systemName: "plus") }
                    .help("Add a row")
                    .disabled(addingConcept)
                Spacer()
            }
            RefusalText(text: model.refusals[.glossary])
            Text("A row is used when translating between two languages it has terms for.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var conceptRows: Int {
        model.configuration.glossary.concepts.count + (addingConcept ? 1 : 0)
    }

    private func concept(at index: Int) -> GlossaryConcept {
        let concepts = model.configuration.glossary.concepts
        if index < concepts.count { return concepts[index] }
        return GlossaryConcept()
    }

    private func conceptRow(_ index: Int, _ concept: GlossaryConcept) -> some View {
        GridRow {
            ForEach(languages, id: \.code) { language in
                CommittingField(
                    placeholder: language.displayName, value: concept.terms[language.code] ?? "",
                    focusOnAppear: index == model.configuration.glossary.concepts.count
                        && language.code == languages.first?.code,
                    commit: { text in
                        model.edit(.glossary) { try $0.setTerm(text, for: language.code, inConcept: index) }
                    })
            }
            Button {
                if index < model.configuration.glossary.concepts.count {
                    model.edit(.glossary) { try $0.deleteConcepts(at: [index]) }
                } else {
                    addingConcept = false
                }
            } label: { Image(systemName: "minus.circle") }
            .buttonStyle(.borderless)
            .help("Delete this row")
        }
    }

    // MARK: - Do not translate

    private var termRows: Int {
        model.configuration.doNotTranslate.count + (addingTerm ? 1 : 0)
    }

    private func termRow(_ index: Int) -> some View {
        let terms = model.configuration.doNotTranslate
        let isNew = index >= terms.count
        return HStack {
            CommittingField(
                placeholder: "Term", value: isNew ? "" : terms[index], focusOnAppear: isNew,
                commit: { text in
                    if !isNew {
                        model.edit(.doNotTranslate) { try $0.setDoNotTranslate(text, at: index) }
                    } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        addingTerm = false
                    } else {
                        model.edit(.doNotTranslate) { try $0.addDoNotTranslate(text) }
                    }
                })
            Button {
                if isNew {
                    addingTerm = false
                } else {
                    model.edit(.doNotTranslate) { try $0.deleteDoNotTranslate(at: [index]) }
                }
            } label: { Image(systemName: "minus.circle") }
            .buttonStyle(.borderless)
            .help("Delete this term")
        }
    }

    private var doNotTranslate: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Do not translate").font(.headline)
            ForEach(0..<termRows, id: \.self) { index in
                termRow(index)
            }
            Button { addingTerm = true } label: { Image(systemName: "plus") }
                .help("Add a term")
                .disabled(addingTerm)
            RefusalText(text: model.refusals[.doNotTranslate])
            Text("Kept exactly as written, capitals included: NORDA protects NORDA, not Norda.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A text field that writes when Return is pressed or it is left, and keeps
/// what is typed while it has focus. Rows are identified by position, so
/// if what is under the field changes while it is typed in (a row above
/// was deleted), the draft is dropped rather than written into another row.
private struct CommittingField: View {
    let placeholder: String
    let value: String
    let focusOnAppear: Bool
    let commit: (String) -> Void

    @State private var draft = ""
    /// `value` when typing began.
    @State private var started = ""
    /// The last text written, trimmed as the file keeps it.
    @State private var sent: String?
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onSubmit { write() }
            .onAppear {
                draft = value
                if focusOnAppear { focused = true }
            }
            .onChange(of: value) {
                if !focused {
                    draft = value
                } else if value == sent {
                    // Our own Return coming back from the file, not another
                    // row moving under the field.
                    started = value
                }
            }
            .onChange(of: focused) { wasFocused, isFocused in
                if isFocused { started = value }
                if wasFocused { write() }
            }
    }

    private func write() {
        if value != started {
            draft = value
            started = value
            return
        }
        if draft == value { return }
        sent = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        commit(draft)
    }
}
