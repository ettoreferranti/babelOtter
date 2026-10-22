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
    private var loop: Task<Void, Never>?
    private var run: Task<Void, Never>?

    init(settings: SettingsModel, environment: @escaping () -> AppEnvironment, startOllama: @escaping () -> Void) {
        self.settings = settings
        self.environment = environment
        self.startOllama = startOllama
        facts = SetupFacts(
            accessibilityGranted: AXIsProcessTrusted(), daemon: nil,
            chosenModel: settings.configuration.model(for: .translate), testSucceeded: false)
    }

    var blocker: String? { SetupFlow.blocker(for: step, facts: facts) }

    // MARK: - Checking

    /// Accessibility every second; Ollama every other second while its
    /// steps show.
    func startChecking() {
        loop?.cancel()
        loop = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self else { return }
                self.facts.accessibilityGranted = AXIsProcessTrusted()
                self.facts.chosenModel = self.settings.configuration.model(for: .translate)
                if tick % 2 == 0 {
                    if self.mode == .full { await self.probe() }
                }
                tick += 1
                try? await Task.sleep(for: .seconds(1))
            }
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
        facts.daemon = probe
        ollamaInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.electron.ollama") != nil
        if case .reachable = probe { settings.loadModelsQuietly() }
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
        settings.edit(.model(.translate)) { editor in
            for action in Action.allCases { try editor.setModel(name, for: action) }
        }
        facts.chosenModel = settings.configuration.model(for: .translate)
    }

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
            switch translator.direction(for: text) {
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
                    self.translationError = PopupModel.describe(error)
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

    init(settings: SettingsModel, environment: @escaping () -> AppEnvironment, startOllama: @escaping () -> Void) {
        model = SetupModel(settings: settings, environment: environment, startOllama: startOllama)
    }

    var isOpen: Bool { window?.isVisible ?? false }

    func showFull() {
        model.mode = .full
        model.step = .accessibility
        present()
    }

    func showAccessibilityOnly() {
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
