import AppKit
import ApplicationServices
import BabelOtterKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    /// The readiness section at the top of the menu: a header per cause with
    /// the command that fixes it, then a separator. Replaced as a block on
    /// every report, in place, so an open menu updates too.
    private var statusLines: [NSMenuItem] = []
    private let source = ConfigurationSource()
    /// Opened once; survives configuration reloads (#67).
    private let history = HistoryRecorder()
    private lazy var historyWindow = HistoryWindowController(
        recorder: history,
        configuration: { [unowned self] in self.environment.configuration })
    /// Recurring mistakes, from History's corrections (#78).
    private lazy var progressWindow = ProgressWindowController(model: ProgressModel(
        store: history.store, unavailable: history.unavailableReason,
        policy: { [unowned self] in self.history.policy },
        configuration: { [unowned self] in self.environment.configuration }))
    private(set) lazy var environment = AppEnvironment(configuration: source.configuration)
    private lazy var monitor = ReadinessMonitor(configuration: source.configuration)
    /// The Ollama inside the app, run while it is the model server (#126).
    private lazy var builtInServer = BuiltInServerController(
        supportDirectory: AppStorage.locator().applicationSupportDirectory(),
        resources: Bundle.main.resourceURL ?? Bundle.main.bundleURL)
    private lazy var watcher: ConfigurationWatcher? = makeWatcher()
    /// Set once, when the configuration folder cannot be watched.
    private var watchProblems: [String] = []

    private var hotKeys: [Action: HotKey] = [:]
    /// The combinations in use; the launch ones until the first plan, so a
    /// typo in the file at launch still leaves Control-Option-T and -C.
    private var combinations = HotKeyPlan.launchCombinations
    private var hotKeyIssues: [HotKeyIssue] = []
    private var actionItems: [Action: NSMenuItem] = [:]
    private var historyItem: NSMenuItem?
    /// "History: off" above History..., while nothing is recorded (#69).
    private var historyNote: NSMenuItem?
    private let layoutReader = KeyboardLayoutReader()
    /// The layout the hotkeys were last resolved against.
    private var lastLayout = KeyLayout(characters: [:])
    private let panel = PopupPanel()
    private var currentModel: PopupModel?
    /// A clipboard capture must always run to its own restore -- cancelling
    /// it mid-flight would abandon that restore and leave the user's real
    /// clipboard clobbered. So a capture in flight is not cancelled; a hotkey
    /// press (or the menu item) received while one is running is dropped
    /// instead, which is simpler and cannot race two captures against the
    /// same pasteboard (Task 5 review finding: two concurrent
    /// `SelectionCapturer.capture` calls can interleave their save/copy/read/
    /// restore sequences on `NSPasteboard.general` and leave the wrong
    /// content on the clipboard).
    private var isCapturing = false
    /// While a settings hotkey recorder listens, no hotkey is registered,
    /// so pressing one records it rather than running its action (#61).
    private var hotKeysSuspended = false
    private lazy var setupWindow: SetupWindowController = SetupWindowController(
        settings: settingsWindow.settingsModel,
        environment: { [unowned self] in self.environment },
        startOllama: { [unowned self] in self.startOllama() },
        restartServer: { [unowned self] in self.builtInServer.restart() })
    /// Kept for the whole run, so its text survives closing it (#84).
    private lazy var scratchpadWindow = ScratchpadWindowController(model: ScratchpadModel(
        environment: { [unowned self] in self.environment },
        record: { [weak self] record in self?.history.record(record) },
        openSetup: { [unowned self] in self.setupWindow.showModelStep() }))
    private lazy var privacyWindow = PrivacyWindowController(
        historyPolicy: { [unowned self] in self.history.policy },
        historyUnavailable: { [unowned self] in self.history.unavailableReason },
        server: { [unowned self] in self.source.configuration.server })
    private lazy var settingsWindow: SettingsWindowController = SettingsWindowController(
        source: source,
        layout: { [unowned self] in self.lastLayout },
        client: { [unowned self] in self.environment.client },
        suspendHotKeys: { [unowned self] in self.suspendHotKeys() },
        resumeHotKeys: { [unowned self] in self.resumeHotKeys() },
        modelsChanged: { [unowned self] in self.monitor.refresh() },
        reloadConfiguration: { [unowned self] in self.configurationChanged() },
        openSetupGuide: { [unowned self] in self.setupWindow.showFull() })

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        updateHotKeys()
        startWatching()
        layoutReader.onChange = { [weak self] in self?.layoutChanged() }
        layoutReader.start()
        pushConfigurationProblems()
        history.onChange = { [weak self] in self?.pushHistoryProblem() }
        history.onRecord = { [weak self] in
            self?.historyWindow.recorded()
            self?.progressWindow.recorded()
        }
        applyHistoryPolicy()
        pushHistoryProblem()
        builtInServer.onChange = { [weak self] state in self?.serverChanged(state) }
        builtInServer.cleanUpLeftover()
        applyModelServer()
        openSetupIfFresh()
        monitor.onChange = { [weak self] report in self?.render(report) }
        render(nil)
        monitor.start()
    }

    /// A popup still open when the app quits keeps its result (#67). The
    /// built-in server never outlives the app (#126).
    func applicationWillTerminate(_ notification: Notification) {
        currentModel?.recordHistory()
        builtInServer.stopAndWait()
    }

    /// Runs the built-in server while it is the model server, and only then
    /// (#126). Called at launch and on every reload; starting a running
    /// server does nothing.
    private func applyModelServer() {
        if source.configuration.server == .builtIn {
            // Only from stopped: a failed server keeps its reason until
            // Restart, rather than restarting on any settings edit.
            if builtInServer.state == .stopped { builtInServer.start() }
        } else {
            builtInServer.stop()
        }
        serverChanged(builtInServer.state)
    }

    private func serverChanged(_ state: BuiltInServerState) {
        var shown: BuiltInServerState?
        if source.configuration.server == .builtIn { shown = state }
        monitor.builtInServer = shown
        settingsWindow.settingsModel.serverState = shown
        setupWindow.serverChanged(shown)
        scratchpadWindow.model.serverState = shown
        monitor.refresh()
    }

    /// Registration stays non-exclusive; a failure reaches the menu as a
    /// cause (#26). Every changed hotkey is released before any is
    /// registered, so Translate and Correct can swap combinations in one save.
    private func updateHotKeys() {
        lastLayout = KeyboardLayoutReader.current()
        if hotKeysSuspended { return }
        let plan = HotKeyPlan.make(
            bindings: source.configuration.hotkeys, previous: combinations, layout: lastLayout)
        let changed = changedActions(to: plan.combinations)
        for action in changed {
            hotKeys[action]?.unregister()
            hotKeys[action] = nil
        }
        for action in changed {
            guard let combination = plan.combinations[action] else { continue }
            hotKeys[action] = HotKey(
                keyCode: combination.keyCode, modifiers: combination.modifiers,
                id: Self.hotKeyID(action)
            ) { [weak self] in self?.startAction(action) }
        }
        combinations = plan.combinations
        hotKeyIssues = plan.issues
        for action in HotKeyPlan.actions {
            actionItems[action]?.title = Self.menuTitle(action, combinations[action])
        }
        var facts: [HotKeyFact] = []
        for action in HotKeyPlan.actions {
            if let combination = combinations[action] {
                facts.append(HotKeyFact(
                    action: action, combination: combination, registered: hotKeys[action] != nil))
            }
        }
        monitor.hotKeys = facts
    }

    private func suspendHotKeys() {
        hotKeysSuspended = true
        for action in HotKeyPlan.actions {
            hotKeys[action]?.unregister()
            hotKeys[action] = nil
        }
    }

    /// Registers the plan again, as the file now has it.
    private func resumeHotKeys() {
        hotKeysSuspended = false
        updateHotKeys()
        // A reload while suspended left the menu's hotkey lines as they were.
        pushConfigurationProblems()
        monitor.refresh()
    }

    /// An action whose keys are the same and still registered is left alone;
    /// one whose registration failed is retried.
    private func changedActions(to wanted: [Action: HotKeyCombination]) -> [Action] {
        var changed: [Action] = []
        for action in HotKeyPlan.actions {
            let new = wanted[action]
            if let old = combinations[action], let new, old.sameKeys(as: new), hotKeys[action] != nil {
                continue
            }
            if combinations[action] == nil, new == nil, hotKeys[action] == nil {
                continue
            }
            changed.append(action)
        }
        return changed
    }

    private static func hotKeyID(_ action: Action) -> UInt32 {
        switch action {
        case .translate: return 1
        case .correct: return 2
        case .explain: return 3
        case .repitch: return 4
        }
    }

    /// "Translate Selection (Control-Option-T)", or without the combination
    /// when the hotkey is off.
    private static func menuTitle(_ action: Action, _ combination: HotKeyCombination?) -> String {
        let base = "\(action.displayName) Selection"
        guard let combination else { return base }
        return "\(base) (\(combination.displayName))"
    }

    private func layoutChanged() {
        updateHotKeys()
        pushConfigurationProblems()
        monitor.refresh()
    }

    // MARK: - Configuration

    private func makeWatcher() -> ConfigurationWatcher? {
        guard let store = source.store else { return nil }
        return ConfigurationWatcher(directory: store.directory, file: store.fileURL)
    }

    private func startWatching() {
        guard let watcher else { return }
        watcher.onChange = { [weak self] in self?.configurationChanged() }
        if !watcher.start() {
            watchProblems = ["changes need a restart: the folder can't be watched"]
        }
    }

    /// Every saved change, applied in one place (#26). A popup already open
    /// keeps the environment it started with.
    private func configurationChanged() {
        source.reload()
        environment = AppEnvironment(configuration: source.configuration)
        monitor.update(configuration: source.configuration)
        applyModelServer()
        updateHotKeys()
        pushConfigurationProblems()
        applyHistoryPolicy()
        settingsWindow.configurationChanged()
        monitor.refresh()
    }

    /// The configuration's retention, or a pause while it is a fallback.
    private func applyHistoryPolicy() {
        history.apply(HistoryPolicy(
            retention: source.configuration.retentionDays,
            configurationIsFallback: source.isFallback))
        renderHistoryNote()
        historyWindow.policyChanged()
        progressWindow.recorded()
    }

    /// Information, not a readiness cause: the icon stays as it is.
    private func renderHistoryNote() {
        guard let menu = statusItem?.menu, let historyItem else { return }
        if let historyNote { menu.removeItem(historyNote) }
        historyNote = nil
        guard let text = history.policy.menuNote else { return }
        let note = NSMenuItem.sectionHeader(title: text)
        menu.insertItem(note, at: menu.index(of: historyItem))
        historyNote = note
    }

    private func pushConfigurationProblems() {
        var problems = source.problems + watchProblems
        for issue in hotKeyIssues {
            problems.append(issue.description)
        }
        monitor.configurationProblems = problems
    }

    private func pushHistoryProblem() {
        monitor.historyProblem = history.problem
        monitor.refresh()
    }

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.attributedTitle = Mascot.menuBarTitle()
        item.button?.toolTip = "lingoSwen"

        let menu = NSMenu()
        menu.delegate = self
        let translateItem = action(Self.menuTitle(.translate, nil), #selector(translateSelectionAction))
        let correctItem = action(Self.menuTitle(.correct, nil), #selector(correctSelectionAction))
        let explainItem = action(Self.menuTitle(.explain, nil), #selector(explainSelectionAction))
        let repitchItem = action(Self.menuTitle(.repitch, nil), #selector(repitchSelectionAction))
        actionItems = [
            .translate: translateItem, .correct: correctItem, .explain: explainItem,
            .repitch: repitchItem,
        ]
        menu.addItem(translateItem)
        menu.addItem(correctItem)
        menu.addItem(explainItem)
        menu.addItem(repitchItem)
        menu.addItem(action("Scratchpad\u{2026}", #selector(showScratchpadAction)))
        menu.addItem(.separator())
        menu.addItem(action("Settings\u{2026}", #selector(showSettingsAction)))
        let historyItem = action("History\u{2026}", #selector(showHistoryAction))
        self.historyItem = historyItem
        menu.addItem(historyItem)
        menu.addItem(action("Progress\u{2026}", #selector(showProgressAction)))
        menu.addItem(action("Privacy\u{2026}", #selector(showPrivacyAction)))
        // Setup Guide and the configuration file are in Settings > General;
        // the status above re-checks each time the menu opens.
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit lingoSwen", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }



    @objc private func showScratchpadAction() { scratchpadWindow.show() }

    @objc private func showHistoryAction() { historyWindow.show() }

    @objc private func showProgressAction() { progressWindow.show() }

    @objc private func showSettingsAction() { settingsWindow.show() }

    @objc private func showPrivacyAction() { privacyWindow.show() }


    /// A fresh install -- no config.json at launch, setup never finished --
    /// is walked through setup (#70); an existing one is left alone. Step 1
    /// asks for Accessibility, so no separate prompt is shown.
    private func openSetupIfFresh() {
        let defaults = UserDefaults.standard
        let existed = source.fileExistedAtLaunch
        let completed = defaults.object(forKey: SetupModel.completedKey) as? Bool
        let opens = SetupGate.shouldOpen(configurationExisted: existed, setupCompleted: completed)
        // Decided once: the first launch writes config.json, so the file
        // cannot answer the question again (a fresh user who closed the
        // window early must see it next time; an existing one never).
        if completed == nil {
            defaults.set(SetupGate.initialCompleted(configurationExisted: existed), forKey: SetupModel.completedKey)
        }
        if opens { setupWindow.showFull() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        // A backstop for a layout change whose notification was held back
        // while babelOtter was inactive.
        if KeyboardLayoutReader.current() != lastLayout {
            layoutChanged()
            return
        }
        monitor.refresh()
    }

    /// Selects config.json, or opens its folder when the file is missing --
    /// which is exactly when this command is offered for "the file is
    /// missing".
    private func showConfiguration() {
        guard let store = source.store else { return }
        if FileManager.default.fileExists(atPath: store.fileURL.path(percentEncoded: false)) {
            NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
        } else {
            NSWorkspace.shared.open(store.directory)
        }
    }

    // MARK: - Readiness

    private func render(_ report: ReadinessReport?) {
        renderIcon(report)
        renderMenu(report)
    }

    private func renderIcon(_ report: ReadinessReport?) {
        guard let button = statusItem?.button else { return }
        let symbol: String?
        switch report?.readiness {
        case .degraded: symbol = "exclamationmark.triangle"
        case .blocked: symbol = "xmark.octagon.fill"
        case .ready, nil: symbol = nil
        }
        let image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageTrailing
        let label = Self.iconLabel(report)
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    private static func iconLabel(_ report: ReadinessReport?) -> String {
        guard let report else { return "lingoSwen: checking" }
        guard let first = report.causes.first else { return "lingoSwen: ready" }
        return "lingoSwen: \(headline(report).lowercased()). \(first.detail)"
    }

    private static func headline(_ report: ReadinessReport?) -> String {
        guard let report else { return "Checking..." }
        switch report.readiness {
        case .ready: return "Ready"
        case .degraded: return "Degraded"
        case .blocked: return "Blocked"
        }
    }

    private func renderMenu(_ report: ReadinessReport?) {
        guard let menu = statusItem?.menu else { return }
        for item in statusLines { menu.removeItem(item) }
        statusLines = makeStatusLines(report)
        var index = 0
        for item in statusLines {
            menu.insertItem(item, at: index)
            index += 1
        }
    }

    /// Status as section headers, so it reads as information, each followed
    /// by the command that fixes it -- never a line that looks like a
    /// disabled command.
    private func makeStatusLines(_ report: ReadinessReport?) -> [NSMenuItem] {
        guard let report else { return [.sectionHeader(title: "Checking\u{2026}"), .separator()] }
        guard !report.causes.isEmpty else { return [.sectionHeader(title: "Ready"), .separator()] }
        var lines: [NSMenuItem] = []
        for cause in report.causes {
            lines.append(.sectionHeader(title: cause.header))
            if let remedy = cause.remedy {
                let item = action(remedy.title, #selector(performRemedy(_:)))
                item.representedObject = remedy
                lines.append(item)
            }
        }
        lines.append(.separator())
        return lines
    }

    @objc private func performRemedy(_ sender: NSMenuItem) {
        guard let remedy = sender.representedObject as? ReadinessRemedy else { return }
        switch remedy {
        case .openAccessibilitySettings:
            // The setup step asks macOS's prompt first, which adds
            // lingoSwen to the list the pane shows (#70).
            setupWindow.showAccessibilityOnly()
        case .startOllama:
            startOllama()
        case .copyPullCommand(let command):
            // Never while a capture or replacement owns the pasteboard.
            guard !isCapturing, currentModel?.isReplacing != true else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        case .restartServer:
            builtInServer.restart()
        case .downloadModel(let model):
            // Setup downloads the model every action shares; one set for
            // a single action is downloaded from its row in Settings.
            if model == environment.configuration.model(for: .translate) {
                setupWindow.showModelStep()
            } else {
                settingsWindow.show()
            }
        case .openKeyboardShortcutsSettings:
            KeyboardShortcutsSettings.open()
        case .showConfiguration:
            showConfiguration()
        }
    }

    /// Launches the Ollama app when it is installed, else opens its download
    /// page. A check follows once the daemon has had time to listen.
    private func startOllama() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.electron.ollama") else {
            if let page = URL(string: "https://ollama.com/download") { NSWorkspace.shared.open(page) }
            return
        }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.monitor.refresh()
        }
    }

    @objc private func translateSelectionAction() { startAction(.translate) }
    @objc private func correctSelectionAction() { startAction(.correct) }
    @objc private func explainSelectionAction() { startAction(.explain) }
    @objc private func repitchSelectionAction() { startAction(.repitch) }

    /// Captures the frontmost application's selection and streams the given
    /// action's result into the popup (NFR-P3/P5: never the text itself,
    /// outside the popup's own view and the clipboard on Copy).
    ///
    /// While a capture or a replacement is already in flight, a fresh press
    /// is ignored outright -- both are pasteboard work that must run to its
    /// own restore rather than being raced or cancelled, and
    /// `ClipboardReplacement`/`ClipboardCapture` share the same
    /// `NSPasteboard.general`, so two of either kind interleaving is exactly
    /// as unsafe as two captures. Only once neither is in flight does a
    /// second press dismiss (and so cancel) the current popup before
    /// starting a new one.
    func startAction(_ action: Action) {
        monitor.refresh()
        guard !isCapturing, currentModel?.isReplacing != true else { return }
        guard AXIsProcessTrusted() else {
            showAccessibilityNeeded(for: action)
            return
        }
        // No text goes to the built-in server's port until lingoSwen has
        // seen its own server answer there (#126); the setup step says why
        // and offers Restart or the download.
        if environment.configuration.server == .builtIn {
            guard builtInServer.state == .running else {
                setupWindow.showModelStep()
                return
            }
        }
        guard let front = NSWorkspace.shared.frontmostApplication,
            front.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        let source = SourceApplication(
            processIdentifier: front.processIdentifier,
            bundleIdentifier: front.bundleIdentifier,
            name: front.localizedName ?? "this application")

        currentModel?.dismiss()

        let model = PopupModel(
            action: action,
            application: source,
            environment: environment,
            record: { [weak self] record in self?.history.record(record) },
            close: { [weak self] in self?.panel.dismiss() },
            reopen: { [weak self] model in
                guard let self else { return }
                self.currentModel = model
                self.panel.show(PopupView(model: model))
            })
        currentModel = model
        // Non-key: the clipboard tier's synthetic Command-C must still reach
        // the source application's own selection, not a key panel of ours.
        panel.show(
            PopupView(model: model), activate: false,
            anchor: SelectionAnchor(processIdentifier: source.processIdentifier).read())

        isCapturing = true
        let capturer = SelectionCapturer(configuration: environment.configuration)
        Task {
            let outcome = await Task.detached { capturer.capture(from: source) }.value
            isCapturing = false
            // A stale result -- from a capture whose popup is no longer the
            // current one -- must never land in a newer popup.
            guard currentModel === model else { return }
            // Capture is over, so the panel can safely take focus now.
            panel.makeKeyNow()
            model.begin(with: outcome)
        }
    }

    /// The setup window at its Accessibility step alone (#71, `FR-ONB-02`):
    /// it re-checks every second, says when the grant is back, and the
    /// action then works without a restart.
    private func showAccessibilityNeeded(for action: Action) {
        currentModel?.dismiss()
        setupWindow.showAccessibilityOnly()
    }
}
