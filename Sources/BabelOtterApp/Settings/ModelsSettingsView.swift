import BabelOtterKit
import SwiftUI

/// The model server (#126), then a model per action, from those installed
/// on it, with a download for a configured one that is not (#60).
struct ModelsSettingsView: View {

    @ObservedObject var model: SettingsModel
    /// The model a download is being confirmed for.
    @State private var confirming: String?
    @State private var confirmingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FileProblemBanner(model: model).padding([.horizontal, .top])
            Form {
                serverSection
                Section {
                    ForEach(Action.allCases, id: \.self) { action in
                        row(action)
                    }
                } footer: {
                    if case .unavailable = model.installed {
                        Text(unavailableNote).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let download = model.download {
                    Section("Download") { progress(download) }
                }
            }
            .formStyle(.grouped)
            .disabled(model.isReadOnly)
        }
        .alert(
            "Download \(confirming ?? "")?",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
        ) {
            Button("Download") {
                if let name = confirming { model.startDownload(name) }
                confirming = nil
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: {
            Text("Ollama downloads it from the internet. A model can be many gigabytes.")
        }
        .alert("Remove the built-in models?", isPresented: $confirmingRemoval) {
            Button("Remove", role: .destructive) { model.removeBuiltInModels() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Switching back to Built-in would download them again.")
        }
        .onAppear { model.measureBuiltInModels() }
    }

    private var unavailableNote: String {
        if model.configuration.server == .builtIn {
            return "The built-in server isn't answering yet."
        }
        return "Ollama isn't running - start it to choose a model."
    }

    @ViewBuilder private var serverSection: some View {
        Section {
            Picker("Model server", selection: Binding(
                get: { model.configuration.server },
                set: { server in model.setModelServer(server) })
            ) {
                ForEach(ModelServer.allCases, id: \.self) { server in
                    Text(server.displayName).tag(server)
                }
            }
            RefusalText(text: model.refusals[.modelServer])
            if let removalFailure = model.removalFailure {
                RefusalText(text: "Not removed: \(removalFailure)")
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(serverNote).font(.caption).foregroundStyle(.secondary)
                if model.configuration.server == .own, let bytes = model.builtInModelsBytes {
                    Button("Remove Built-in Models (\(DiskSpacePolicy.gigabytes(bytes)))\u{2026}") {
                        confirmingRemoval = true
                    }
                    .disabled(model.isReadOnly)
                }
            }
        }
    }

    private var serverNote: String {
        if let state = model.serverState { return state.status }
        return "lingoSwen uses the Ollama you run yourself, on this Mac."
    }

    @ViewBuilder private func row(_ action: Action) -> some View {
        let configured = model.configuration.model(for: action)
        if let choice = model.choice(for: action) {
            VStack(alignment: .leading, spacing: 4) {
                Picker(action.displayName, selection: Binding(
                    get: { configured },
                    set: { name in model.edit(.model(action)) { try $0.setModel(name, for: action) } })
                ) {
                    ForEach(choice.options, id: \.self) { name in
                        Text(name == configured && !choice.isInstalled ? "\(name) (not installed)" : name)
                            .tag(name)
                    }
                }
                if !choice.isInstalled {
                    HStack {
                        Text("\(configured) is not installed.").font(.caption).foregroundStyle(.secondary)
                        Button("Download\u{2026}") { confirming = configured }
                            .disabled(model.download?.running == true)
                    }
                }
                RefusalText(text: model.refusals[.model(action)])
            }
        } else {
            LabeledContent(action.displayName, value: configured)
        }
    }

    @ViewBuilder private func progress(_ download: ModelDownload) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(download.model).font(.callout.weight(.semibold))
            if let failure = download.failure {
                Text("Download failed: \(failure)").font(.caption).foregroundStyle(.red)
            } else if download.running {
                if let fraction = download.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(download.status).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Downloaded.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
