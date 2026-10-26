import AppKit
import ApplicationServices
import BabelOtterKit
import SwiftUI

/// What the setup window shows (#70, #71).
enum SetupMode: Equatable {
    /// Every step, from the first: a fresh install or Setup Guide...
    case full
    /// Accessibility alone: it went missing and an action was triggered.
    case accessibilityOnly
}

/// The setup window's state. Facts are re-read by a loop while the window
/// is open: macOS posts nothing when Accessibility is granted.
@MainActor
final class SetupModel: ObservableObject {

    static let completedKey = "setupCompleted"

    @Published var mode = SetupMode.full
    @Published var step = SetupStep.accessibility
    @Published private(set) var facts: SetupFacts
    @Published private(set) var ollamaInstalled = true
    @Published private(set) var translation = ""
    @Published private(set) var translationError: String?
    @Published private(set) var translating = false
    @Published var sentence = SetupFlow.sampleSentence

    let settings: SettingsModel
    private let environment: () -> AppEnvironment
    private let startOllama: () -> Void
    private let restartServer: () -> Void
    private var loop: Task<Void, Never>?
    private var run: Task<Void, Never>?
    private var probing = false
    /// The user's own Ollama, probed to offer it when it has the model (#126).
    private let ownClient = OllamaClient.loopback(.loopback, timeout: 2)
    /// A fresh install's server is chosen once, from the first probe of the
    /// user's own Ollama (#126).
    private var initialServerChosen = false

    init(
        settings: SettingsModel, environment: @escaping () -> AppEnvironment,
        startOllama: @escaping () -> Void, restartServer: @escaping () -> Void
    ) {
        self.settings = settings
        self.environment = environment
        self.startOllama = startOllama
        self.restartServer = restartServer
        facts = SetupFacts(
            accessibilityGranted: AXIsProcessTrusted(), server: settings.configuration.server,
            builtInServer: settings.serverState, daemon: nil,
            chosenModel: settings.configuration.model(for: .translate), testSucceeded: false)
    }

    var blocker: String? { SetupFlow.blocker(for: step, facts: facts) }

    // MARK: - Checking

    /// Accessibility every second; Ollama every other second while a step
    /// that needs it shows, in its own task so a slow answer never delays
    /// the Accessibility check.
    func startChecking() {
        loop?.cancel()
        loop = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self else { return }
                self.facts.accessibilityGranted = AXIsProcessTrusted()
                self.facts.chosenModel = self.settings.configuration.model(for: .translate)
                self.facts.server = self.settings.configuration.server
                if tick % 2 == 0 {
                    if self.needsOllama { self.probeInBackground() }
                }
                tick += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var needsOllama: Bool {
        if mode != .full { return false }
        return step == .model
    }

    private func probeInBackground() {
        if probing { return }
        probing = true
        Task { [weak self] in
            await self?.probe()
            self?.probing = false
        }
    }

    func stopChecking() {
        loop?.cancel()
        loop = nil
        run?.cancel()
    }

    private func probe() async {
        let client = environment().client
        let probe = await client.probe()
        let own = await ownClient.probe()
        facts.daemon = probe
        facts.ownOllama = own
        ollamaInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.electron.ollama") != nil
        chooseInitialServer(own)
    }

    /// On a fresh install, once: the user's own Ollama when it already has
    /// the model, else the built-in server the defaults name (#126).
    private func chooseInitialServer(_ own: DaemonProbe) {
        if initialServerChosen { return }
        initialServerChosen = true
        if UserDefaults.standard.bool(forKey: Self.completedKey) { return }
        let server = SetupFlow.initialServer(ownOllama: own)
        if server != settings.configuration.server { chooseServer(server) }
    }

    /// The built-in server's state changed, or the model server did.
    func serverChanged(_ state: BuiltInServerState?) {
        facts.builtInServer = state
        facts.server = settings.configuration.server
    }

    func chooseServer(_ server: ModelServer) {
        settings.setModelServer(server)
        facts.server = settings.configuration.server
        facts.daemon = nil
        resetTest()
    }

    func restart() {
        restartServer()
    }

    /// Why Download may not start, if it may not: too little free space.
    var diskRefusal: String? {
        let folder = settings.builtInFiles.directory.deletingLastPathComponent()
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values?.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskSpacePolicy.refusal(availableBytes: available)
    }

    /// The built-in model's download, after the disk check.
    func downloadBuiltIn() {
        if diskRefusal != nil { return }
        settings.startDownload(facts.chosenModel)
    }

    /// A fresh walk-through, or another model: the test is due again.
    func resetTest() {
        run?.cancel()
        facts.testSucceeded = false
        translation = ""
        translationError = nil
    }

    // MARK: - Steps

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        AccessibilitySettings.open()
    }

    func openOllama() {
        startOllama()
    }

    /// The same model for every action.
    func chooseModel(_ name: String) {
        let written = settings.edit(.model(.translate)) { editor in
            for action in Action.allCases { try editor.setModel(name, for: action) }
        }
        facts.chosenModel = settings.configuration.model(for: .translate)
        if written { resetTest() }
    }

    /// Why the last model choice was not written, if it was not.
    var modelRefusal: String? { settings.refusals[.model(.translate)] }

    func next() {
        guard blocker == nil else { return }
        guard let following = SetupStep(rawValue: step.rawValue + 1) else { return }
        step = following
    }

    func back() {
        guard let previous = SetupStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// The real pipeline on the sample, streamed.
    func translate() {
        run?.cancel()
        translation = ""
        translationError = nil
        translating = true
        let environment = environment()
        let translator = Translator(configuration: environment.configuration, chat: environment.client)
        let text = UserText(sentence)
        run = Task { [weak self] in
            guard let self else { return }
            defer { self.translating = false }
            var resolved = translator.direction(for: text, remembered: TargetMemory().remembered)
            // Three or more languages and no target remembered for English:
            // the first other one, so the test never stops to ask (#81).
            if case .failure(.directionUnknown(let source?, let candidates)) = resolved, let first = candidates.first {
                resolved = .success(Direction(source: source, target: first))
            }
            switch resolved {
            case .failure(let error):
                self.translationError = PopupModel.describe(error)
                return
            case .success(let direction):
                let profile = environment.configuration.profiles.first ?? .colleagues
                do {
                    for try await event in translator.translate(text, direction: direction, profile: profile) {
                        switch event {
                        case .preview(let partial): self.translation = partial.value
                        case .finished(let result):
                            self.translation = result.text.value
                            self.facts.testSucceeded = true
                        default: break
                        }
                    }
                } catch {
                    // Closing the window cancels the run: not a failure.
                    if !Task.isCancelled { self.translationError = PopupModel.describe(error) }
                }
            }
        }
    }
}

/// Set Up lingoSwen (#70), or its Accessibility step alone (#71).
@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {

    private let model: SetupModel
    private var window: AppWindow?

    init(
        settings: SettingsModel, environment: @escaping () -> AppEnvironment,
        startOllama: @escaping () -> Void, restartServer: @escaping () -> Void
    ) {
        model = SetupModel(
            settings: settings, environment: environment, startOllama: startOllama,
            restartServer: restartServer)
    }

    func serverChanged(_ state: BuiltInServerState?) {
        model.serverChanged(state)
    }

    /// The Model step, for the menu's Download remedy (#126): over a full
    /// walk-through already open, it moves there.
    func showModelStep() {
        if !isOpen { model.resetTest() }
        model.mode = .full
        model.step = .model
        present()
    }

    var isOpen: Bool { window?.isVisible ?? false }

    func showFull() {
        model.mode = .full
        model.step = .accessibility
        model.resetTest()
        present()
    }

    /// Over a full walk-through already open, only moves it to the step,
    /// keeping its place in setup.
    func showAccessibilityOnly() {
        if isOpen {
            if model.mode == .full {
                model.step = .accessibility
                window?.present()
                return
            }
        }
        model.mode = .accessibilityOnly
        model.step = .accessibility
        present()
    }

    func windowWillClose(_ notification: Notification) {
        model.stopChecking()
    }

    /// Finish: setup is done and does not open by itself again.
    fileprivate func finish() {
        UserDefaults.standard.set(true, forKey: SetupModel.completedKey)
        window?.performClose(nil)
    }

    fileprivate func close() {
        window?.performClose(nil)
    }

    private func present() {
        let window = self.window ?? makeWindow()
        self.window = window
        model.startChecking()
        window.present()
    }

    private func makeWindow() -> AppWindow {
        let view = SetupView(
            model: model, finish: { [weak self] in self?.finish() }, close: { [weak self] in self?.close() })
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        let window = AppWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "Set Up lingoSwen"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }
}
