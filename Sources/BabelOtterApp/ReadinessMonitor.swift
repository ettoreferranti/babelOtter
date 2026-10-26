import AppKit
import ApplicationServices
import BabelOtterKit
import Carbon.HIToolbox

/// Gathers the readiness facts and runs `ReadinessPolicy` over them.
///
/// Checks on a 30 s loop and on wake by itself; `AppDelegate` also asks for a
/// check when the menu opens and when an action is triggered. A check already
/// running is joined, not duplicated, so a slow daemon never stacks probes.
@MainActor
final class ReadinessMonitor {

    /// nil until the first check finishes.
    private(set) var report: ReadinessReport?
    /// Set once by `AppDelegate`, after registering the hotkeys.
    var hotKeys: [HotKeyFact] = []
    /// Set by `AppDelegate` at launch and on every reload.
    var configurationProblems: [String] = []
    /// Set by `AppDelegate` whenever history starts or stops saving (#67).
    var historyProblem: String?
    /// Set by `AppDelegate` on every state change while the built-in server
    /// is in use; nil for the user's own Ollama (#126).
    var builtInServer: BuiltInServerState?
    var onChange: (@MainActor (ReadinessReport) -> Void)?

    private var client: OllamaClient
    private var models: [Action: String]
    private var inFlight: Task<Void, Never>?
    private var loop: Task<Void, Never>?
    private var wakeObserver: (any NSObjectProtocol)?

    private static let interval = Duration.seconds(30)
    /// A tags request answers in milliseconds. The generation timeout, which
    /// a user may raise to minutes for a slow model, would leave a hung check
    /// joined by every Check Again, menu open and hotkey press until it ends.
    private static let probeTimeout: TimeInterval = 5

    init(configuration: Configuration) {
        client = OllamaClient.loopback(configuration.endpoint, timeout: Self.probeTimeout)
        models = Self.models(for: configuration)
    }

    /// A reload changes the models checked, and the server asked, from the
    /// next check on (#26, #126).
    func update(configuration: Configuration) {
        models = Self.models(for: configuration)
        client = OllamaClient.loopback(configuration.endpoint, timeout: Self.probeTimeout)
    }

    /// Every action is checked. One without a configured model falls back to
    /// the default, as the pipeline does.
    private static func models(for configuration: Configuration) -> [Action: String] {
        var models: [Action: String] = [:]
        for action in Action.allCases {
            models[action] = configuration.model(for: action)
        }
        return models
    }

    func start() {
        refresh()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                self?.refresh()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        guard inFlight == nil else { return }
        inFlight = Task { [weak self] in
            await self?.check()
        }
    }

    private func check() async {
        let granted = AXIsProcessTrusted()
        let probe = await client.probe()
        let facts = ReadinessFacts(
            accessibilityGranted: granted, probe: probe, models: models,
            hotKeys: hotKeys, systemShortcuts: Self.systemShortcuts(),
            configurationProblems: configurationProblems, historyProblem: historyProblem,
            builtInServer: builtInServer)
        let report = ReadinessPolicy().report(for: facts)
        self.report = report
        inFlight = nil
        onChange?(report)
    }

    /// Read on every check, so a shortcut changed in System Settings shows up
    /// without a relaunch.
    private static func systemShortcuts() -> [SystemShortcut] {
        var array: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&array) == noErr,
            let entries = array?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        var shortcuts: [SystemShortcut] = []
        for entry in entries {
            guard let code = entry[kHISymbolicHotKeyCode as String] as? Int,
                let modifiers = entry[kHISymbolicHotKeyModifiers as String] as? Int
            else { continue }
            let enabled = entry[kHISymbolicHotKeyEnabled as String] as? Bool ?? false
            shortcuts += [
                SystemShortcut(
                    keyCode: UInt32(truncatingIfNeeded: code),
                    modifiers: SystemShortcut.carbonModifiers(fromSymbolic: modifiers),
                    enabled: enabled)
            ]
        }
        return shortcuts
    }
}

/// Privacy & Security > Accessibility, where the grant is made.
enum AccessibilitySettings {
    @MainActor static func open() {
        let address = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}

enum KeyboardShortcutsSettings {
    @MainActor static func open() {
        let address = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}
