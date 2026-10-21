import BabelOtterKit
import SwiftUI

/// The audiences: the list on the left, the selected one on the right (#61).
/// Closures rather than method references throughout: Swift 6.1 crashed on
/// the latter in a view (PR #108).
struct AudiencesSettingsView: View {

    @ObservedObject var model: SettingsModel
    @State private var selection: String?
    @State private var confirmingDelete: AudienceProfile?
    /// The name being typed for a new audience; nil when not adding.
    @State private var newName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FileProblemBanner(model: model).padding([.horizontal, .top])
            HStack(alignment: .top, spacing: 0) {
                list.frame(width: 190)
                Divider()
                detail.frame(maxWidth: .infinity)
            }
            .disabled(model.isReadOnly)
        }
        .onAppear { selectFirstIfNeeded() }
        .onChange(of: model.configuration.profiles) { selectFirstIfNeeded() }
        .onChange(of: model.addedAudience) {
            if let added = model.addedAudience { selection = added }
        }
        .alert(
            "New audience",
            isPresented: Binding(get: { newName != nil }, set: { if !$0 { newName = nil } })
        ) {
            TextField("Name", text: Binding(get: { newName ?? "" }, set: { newName = $0 }))
            Button("Add") {
                if let name = newName { _ = model.addAudience(named: name) }
                newName = nil
            }
            Button("Cancel", role: .cancel) { newName = nil }
        } message: {
            Text("Its id is made from this name and stays when it is renamed.")
        }
        .alert(
            "Delete \(confirmingDelete?.name ?? "")?",
            isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let profile = confirmingDelete {
                    model.edit(.audiences) { try $0.deleteAudience(profile.id) }
                }
                confirmingDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        } message: {
            Text("Its tone guidance is lost.")
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            List(selection: $selection) {
                ForEach(model.configuration.profiles, id: \.id) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            HStack {
                Button { newName = "" } label: { Image(systemName: "plus") }
                    .help("Add an audience")
                Button("Delete\u{2026}") {
                    confirmingDelete = model.configuration.profiles.first { $0.id == selection }
                }
                .disabled(selection == nil || model.configuration.profiles.count <= 1)
            }
            .padding(.horizontal, 8)
            Button("Restore shipped audiences") { model.restoreShippedAudiences() }
                .disabled(!model.canRestoreAudiences)
                .padding(.horizontal, 8)
            if let note = model.audienceNote {
                Text(note).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            RefusalText(text: model.refusals[.audiences]).padding(.horizontal, 8)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder private var detail: some View {
        if let id = selection {
            if let profile = model.configuration.profile(id: id) {
                AudienceDetail(model: model, profile: profile).id(id)
            }
        } else {
            Text("Select an audience").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func selectFirstIfNeeded() {
        if let selection {
            if model.configuration.profile(id: selection) != nil { return }
        }
        selection = model.configuration.profiles.first?.id
    }
}

/// One audience's fields. Text is written when the field is left, or on
/// Return (Command-Return in the multi-line ones).
private struct AudienceDetail: View {

    @ObservedObject var model: SettingsModel
    let profile: AudienceProfile

    @State private var name = ""
    @State private var guidance = ""
    @State private var terms = ""
    @FocusState private var focused: AudienceField?

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .focused($focused, equals: .name)
                    .onSubmit { commitName() }
                Text("id: \(profile.id)").font(.caption).foregroundStyle(.secondary)
                RefusalText(text: refusal(.name))
                Picker("Register", selection: Binding(
                    get: { profile.register },
                    set: { register in
                        model.edit(.audience(profile.id, .register)) {
                            try $0.setRegister(register, forAudience: profile.id)
                        }
                    })
                ) {
                    Text("Sie").tag(Register.formal)
                    Text("du").tag(Register.informal)
                }
                .pickerStyle(.segmented)
            }
            Section("Tone guidance") {
                TextEditor(text: $guidance)
                    .focused($focused, equals: .guidance)
                    .frame(height: 90)
                    .onKeyPress(keys: [.return], phases: .down) { press in
                        if !press.modifiers.contains(.command) { return .ignored }
                        commitGuidance()
                        return .handled
                    }
                RefusalText(text: refusal(.guidance))
            }
            Section("Preferred terms, one per line") {
                TextEditor(text: $terms)
                    .focused($focused, equals: .terms)
                    .frame(height: 70)
                    .onKeyPress(keys: [.return], phases: .down) { press in
                        if !press.modifiers.contains(.command) { return .ignored }
                        commitTerms()
                        return .handled
                    }
                RefusalText(text: refusal(.terms))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            resetDrafts()
            if model.addedAudience == profile.id {
                focused = .name
                model.addedAudience = nil
            }
        }
        .onChange(of: profile) { resetDrafts() }
        .onChange(of: focused) { old, _ in
            if old == .name { commitName() }
            if old == .guidance { commitGuidance() }
            if old == .terms { commitTerms() }
        }
        .onDisappear {
            // Leaving the audience (another selected, the tab switched)
            // writes what was being typed.
            if let field = focused {
                switch field {
                case .name: commitName()
                case .guidance: commitGuidance()
                case .terms: commitTerms()
                case .register: break
                }
            }
            model.noteRefusalsOnLeaving(profile.name, of: profile.id)
        }
    }

    private func refusal(_ field: AudienceField) -> String? {
        model.refusals[.audience(profile.id, field)]
    }

    private func commitName() {
        if name == profile.name { return }
        model.edit(.audience(profile.id, .name)) { try $0.renameAudience(profile.id, to: name) }
    }

    private func commitGuidance() {
        if guidance == profile.toneGuidance { return }
        model.edit(.audience(profile.id, .guidance)) { try $0.setToneGuidance(guidance, forAudience: profile.id) }
    }

    private func commitTerms() {
        if terms == profile.glossaryBias.joined(separator: "\n") { return }
        model.edit(.audience(profile.id, .terms)) { try $0.setPreferredTerms(terms, forAudience: profile.id) }
    }

    /// A field being typed in keeps what is typed.
    private func resetDrafts() {
        if focused != .name { name = profile.name }
        if focused != .guidance { guidance = profile.toneGuidance }
        if focused != .terms { terms = profile.glossaryBias.joined(separator: "\n") }
    }
}
