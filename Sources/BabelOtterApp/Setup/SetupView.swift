import BabelOtterKit
import SwiftUI

/// The setup window's content. Closures rather than method references
/// throughout: Swift 6.1 crashed on the latter in a view (PR #108).
struct SetupView: View {

    @ObservedObject var model: SetupModel
    let finish: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if model.mode == .full {
                sidebar.frame(width: 160)
                Divider()
            }
            VStack(alignment: .leading, spacing: 16) {
                content
                Spacer(minLength: 0)
                footer
            }
            .padding(20)
            .frame(width: 460, alignment: .leading)
        }
        .frame(height: 400)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(SetupStep.allCases, id: \.self) { step in
                HStack(spacing: 6) {
                    Image(systemName: icon(step))
                        .foregroundStyle(step == model.step ? Color.accentColor : .secondary)
                    Text(step.title).fontWeight(step == model.step ? .semibold : .regular)
                }
            }
            Spacer()
        }
        .padding(16)
    }

    private func icon(_ step: SetupStep) -> String {
        if step < model.step { return "checkmark.circle.fill" }
        if step == model.step { return "circle.inset.filled" }
        return "circle"
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .accessibility: accessibility
        case .model: modelStep
        case .hotkeys: HotKeysSettingsView(model: model.settings)
        case .tryIt: tryIt
        }
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accessibility").font(.title2.weight(.semibold))
            Text("lingoSwen reads the text you select and pastes the result back. macOS asks your permission for that, under Accessibility.")
                .fixedSize(horizontal: false, vertical: true)
            if model.facts.accessibilityGranted {
                status(true, model.mode == .accessibilityOnly ? "Granted - try the action again." : "Granted.")
            } else {
                status(false, "Not granted yet. Turn lingoSwen on in the list, then come back: this updates by itself.")
                Button("Open Accessibility Settings") { model.requestAccessibility() }
            }
        }
    }

    /// One step for the model server and its model (#126): the built-in
    /// server and its download, or the user's own Ollama and its models.
    private var modelStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Model").font(.title2.weight(.semibold))
            if SetupFlow.offersOwnOllama(model.facts) {
                Text("Ollama is already on this Mac, with \(BuiltInServer.modelDisplayName).")
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Model server", selection: Binding(
                    get: { model.facts.server },
                    set: { server in model.chooseServer(server) })
                ) {
                    Text("Use My Ollama").tag(ModelServer.own)
                    Text("Use Built-in (a separate \(BuiltInServer.downloadSizeText) download)").tag(ModelServer.builtIn)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .disabled(model.settings.isReadOnly)
            }
            if model.facts.server == .builtIn {
                builtInModel
            } else {
                ownModel
            }
        }
    }

    @ViewBuilder private var builtInModel: some View {
        let name = SetupFlow.displayName(of: model.facts.chosenModel)
        Text("lingoSwen sets up its own model: \(name), a \(BuiltInServer.downloadSizeText) download from Ollama's library. Nothing you translate leaves the Mac.")
            .fixedSize(horizontal: false, vertical: true)
        switch model.facts.builtInServer ?? .stopped {
        case .stopped, .starting:
            status(nil, BuiltInServerState.starting.status)
        case .failed(let reason):
            status(false, BuiltInServerState.failed(reason).status)
            Button("Restart") { model.restart() }
        case .running:
            if case .reachable(let names)? = model.facts.daemon {
                if names.contains(model.facts.chosenModel) {
                    status(true, "\(name) is downloaded.")
                } else if let download = model.settings.download {
                    downloadStatus(download)
                } else if let refusal = model.diskRefusal {
                    status(false, refusal)
                } else {
                    Button("Download") { model.downloadBuiltIn() }
                }
            } else {
                status(nil, BuiltInServerState.starting.status)
            }
        }
    }

    @ViewBuilder private var ownModel: some View {
        Text("lingoSwen uses your Ollama on this Mac. Nothing you translate leaves the Mac. You can choose a model per action later, in Settings.")
            .fixedSize(horizontal: false, vertical: true)
        switch model.facts.daemon {
        case .none:
            status(nil, "Checking\u{2026}")
        case .unreachable?:
            status(false, model.ollamaInstalled ? "Ollama isn't running." : "Ollama isn't installed.")
            Button(model.ollamaInstalled ? "Start Ollama" : "Get Ollama") { model.openOllama() }
        case .reachable(let names)?:
            let choice = ModelChoice(configured: model.facts.chosenModel, installed: names)
            Picker("Model", selection: Binding(
                get: { model.facts.chosenModel },
                set: { name in model.chooseModel(name) })
            ) {
                ForEach(choice.options, id: \.self) { name in Text(name).tag(name) }
            }
            .fixedSize()
            .disabled(model.settings.isReadOnly)
            if let refusal = model.modelRefusal {
                Text(refusal).font(.caption).foregroundStyle(.red)
            }
            if choice.isInstalled {
                status(true, "\(model.facts.chosenModel) is installed.")
            } else if let download = model.settings.download {
                downloadStatus(download)
            } else {
                status(false, "\(model.facts.chosenModel) is not installed.")
                Button("Download\u{2026}") { model.settings.startDownload(model.facts.chosenModel) }
                Text("Ollama downloads it from the internet; a model can be many gigabytes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func downloadStatus(_ download: ModelDownload) -> some View {
        if let failure = download.failure {
            status(false, "Download failed: \(failure)")
            Button("Download Again") { model.settings.startDownload(model.facts.chosenModel) }
        } else if download.running {
            if let fraction = download.fraction { ProgressView(value: fraction) } else { ProgressView() }
            HStack {
                Text(download.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.settings.cancelDownload() }
            }
        } else {
            status(nil, "Downloaded; checking\u{2026}")
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try it").font(.title2.weight(.semibold))
            Text("Translate a sentence with the model you chose. Edit it if you like.")
            TextField("Sentence", text: $model.sentence, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Translate") { model.translate() }
                    .disabled(model.translating)
                if model.translating { ProgressView().controlSize(.small) }
            }
            if !model.translation.isEmpty {
                Text(model.translation)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            if let error = model.translationError {
                status(false, error)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let blocker = model.blocker {
                Text(blocker).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.mode == .accessibilityOnly {
                Button("Done") { close() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.blocker != nil)
            } else {
                if model.step != .accessibility {
                    Button("Back") { model.back() }
                }
                if model.step == .tryIt {
                    Button("Finish") { finish() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.blocker != nil)
                } else {
                    Button("Continue") { model.next() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.blocker != nil)
                }
            }
        }
    }

    /// true a check, false a cross, nil a pending mark.
    private func status(_ ok: Bool?, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            switch ok {
            case .some(true): Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .some(false): Image(systemName: "xmark.circle.fill").foregroundStyle(.orange)
            case .none: Image(systemName: "clock").foregroundStyle(.secondary)
            }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
