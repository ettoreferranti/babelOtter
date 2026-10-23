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

    /// A column per enabled language (#81); a switched-off language's terms
    /// stay in the file untouched.
    private var languages: [LanguageConfig] { model.configuration.enabledLanguages }

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
        // The new row goes once it has been saved -- the list grew -- not
        // on any other change, which would take it away mid-typing.
        .onChange(of: model.configuration.glossary.concepts.count) { old, new in
            if new > old { addingConcept = false }
        }
        .onChange(of: model.configuration.doNotTranslate.count) { old, new in
            if new > old { addingTerm = false }
        }
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

    /// The row as a whole, and where it is: an empty cell in another row
    /// looks the same as this one, the whole row does not.
    private static func identity(_ index: Int, _ concept: GlossaryConcept) -> String {
        let terms = concept.terms.map { $0.key.rawValue + "=" + $0.value }.sorted()
        return String(index) + "|" + terms.joined(separator: "|")
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
                    identity: Self.identity(index, concept),
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
                placeholder: "Term", value: isNew ? "" : terms[index],
                identity: String(index) + "|" + (isNew ? "" : terms[index]), focusOnAppear: isNew,
                commit: { text in
                    if !isNew {
                        return model.edit(.doNotTranslate) { try $0.setDoNotTranslate(text, at: index) }
                    }
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        addingTerm = false
                        return true
                    }
                    return model.edit(.doNotTranslate) { try $0.addDoNotTranslate(text) }
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
/// if the row under the field changes while it is typed in (a row above was
/// deleted), the draft is dropped rather than written into another row. A
/// refused draft goes back to the saved value; the reason stays shown.
private struct CommittingField: View {
    let placeholder: String
    let value: String
    /// The row as a whole; it changes when another row moves under the field.
    let identity: String
    let focusOnAppear: Bool
    /// False when the value was refused.
    let commit: (String) -> Bool

    @State private var draft = ""
    /// `identity` when typing began.
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
                    started = identity
                }
            }
            // A sibling cell saving (Tab out of the first cell of a new row)
            // changes the row before anything is typed here: nothing to
            // protect yet, so start from the row as it now is.
            .onChange(of: identity) {
                if focused {
                    if draft == value { started = identity }
                }
            }
            .onChange(of: focused) { wasFocused, isFocused in
                if isFocused { started = identity }
                if wasFocused { write() }
            }
    }

    private func write() {
        if identity != started {
            draft = value
            started = identity
            return
        }
        if draft == value { return }
        sent = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !commit(draft) {
            draft = value
            sent = nil
        }
    }
}
