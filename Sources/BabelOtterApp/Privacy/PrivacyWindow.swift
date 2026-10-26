import AppKit
import BabelOtterKit
import SwiftUI

/// The facts the Privacy panel is built from, gathered by the app (#72).
@MainActor
final class PrivacyModel: ObservableObject {

    @Published private(set) var lines: [PrivacyLine] = []
    @Published private(set) var checking = false
    @Published var copied = false

    private let historyPolicy: () -> HistoryPolicy
    private let historyUnavailable: () -> String?
    private let server: () -> ModelServer
    /// Only the latest check's result is shown.
    private var generation = 0
    private var copies = 0

    init(
        historyPolicy: @escaping () -> HistoryPolicy, historyUnavailable: @escaping () -> String?,
        server: @escaping () -> ModelServer
    ) {
        self.historyPolicy = historyPolicy
        self.historyUnavailable = historyUnavailable
        self.server = server
    }

    /// The bundled copy, nil when running outside the app bundle.
    var privacyDocument: URL? {
        Bundle.main.url(forResource: "PRIVACY", withExtension: "md")
    }

    /// Clears what is shown first: an earlier check must not stand in for
    /// this one while it runs.
    func check() {
        generation += 1
        let current = generation
        lines = []
        checking = true
        let server = server()
        Task {
            let listening = await ListeningProbeRunner.run(port: server.endpoint.port)
            let locator = AppStorage.locator()
            let folder = locator.applicationSupportDirectory()
            var refusal: StorageLocationError?
            var unavailable = historyUnavailable()
            do {
                try locator.validate(folder)
            } catch let error as StorageLocationError {
                refusal = error
            } catch {
                // Never read an unexpected failure as "accepted".
                unavailable = error.localizedDescription
            }
            guard current == generation else { return }
            lines = PrivacyReport.lines(
                server: server, endpoint: server.endpoint, listening: listening,
                historyFolder: Self.abbreviated(folder), historyRefusal: refusal,
                historyUnavailable: unavailable, history: historyPolicy())
            checking = false
        }
    }

    func copy(_ command: String) {
        SystemPasteboard().write(command, concealed: false)
        copied = true
        copies += 1
        let current = copies
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if current == copies { copied = false }
        }
    }

    func openDocument() {
        guard let url = privacyDocument else { return }
        NSWorkspace.shared.open(url)
    }

    /// "~/Library/..." rather than the full home path.
    private static func abbreviated(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        if path.hasPrefix(home) { return "~/" + path.dropFirst(home.count).drop { $0 == "/" } }
        return path
    }
}

/// Privacy... in the menu (#72): one window, re-checked each time it opens.
@MainActor
final class PrivacyWindowController {

    private let model: PrivacyModel
    private var window: AppWindow?

    init(
        historyPolicy: @escaping () -> HistoryPolicy, historyUnavailable: @escaping () -> String?,
        server: @escaping () -> ModelServer
    ) {
        model = PrivacyModel(historyPolicy: historyPolicy, historyUnavailable: historyUnavailable, server: server)
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        model.check()
        window.present()
    }

    private func makeWindow() -> AppWindow {
        let controller = NSHostingController(rootView: PrivacyView(model: model))
        controller.sizingOptions = [.preferredContentSize]
        let window = AppWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "Privacy"
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("PrivacyWindow")
        return window
    }
}

struct PrivacyView: View {

    @ObservedObject var model: PrivacyModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(model.lines, id: \.title) { line in
                row(line)
            }
            if model.lines.isEmpty {
                ProgressView().controlSize(.small)
            }
            Divider()
            Text(PrivacyReport.clipboardNote).font(.callout).foregroundStyle(.secondary)
            HStack {
                if model.privacyDocument == nil {
                    Text("PRIVACY.md is in the repository.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Open PRIVACY.md") { model.openDocument() }
                }
                Spacer()
                Button("Check Again") { model.check() }
                    .disabled(model.checking)
            }
        }
        .padding(20)
        .frame(width: 520, alignment: .leading)
    }

    private func row(_ line: PrivacyLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            mark(line.mark)
            VStack(alignment: .leading, spacing: 4) {
                Text(line.title).font(.headline)
                Text(line.detail).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                if let remedy = line.remedy {
                    Text("Run this in Terminal, then quit and restart Ollama:").font(.callout)
                    HStack {
                        Text(remedy).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        Button(model.copied ? "Copied" : "Copy") { model.copy(remedy) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func mark(_ mark: PrivacyLine.Mark) -> some View {
        switch mark {
        case .ok:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .accessibilityLabel("As it should be")
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                .accessibilityLabel("Warning")
        case .unknown:
            Image(systemName: "questionmark.circle.fill").foregroundStyle(.secondary)
                .accessibilityLabel("Unknown")
        }
    }
}
