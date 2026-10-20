import BabelOtterKit
import SwiftUI

/// A model per action, from those installed in Ollama, with a download for
/// a configured one that is not (#60).
struct ModelsSettingsView: View {

    @ObservedObject var model: SettingsModel
    /// The model a download is being confirmed for.
    @State private var confirming: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FileProblemBanner(model: model).padding([.horizontal, .top])
            Form {
                Section {
                    ForEach(Action.allCases, id: \.self) { action in
                        row(action)
                    }
                } footer: {
                    if case .unavailable = model.installed {
                        Text("Ollama isn't running - start it to choose a model.")
                            .font(.caption).foregroundStyle(.secondary)
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
