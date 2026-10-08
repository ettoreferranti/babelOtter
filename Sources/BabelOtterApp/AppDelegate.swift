import AppKit
import ApplicationServices
import BabelOtterKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    /// Hidden unless `environment.configurationNote` has something to say --
    /// most launches have nothing wrong with the config file, and a menu
    /// line reporting that would be noise.
    private let configLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    /// The readiness lines: a headline, one line per cause, and "Open
    /// Accessibility Settings..." when that is a cause. Replaced as a block on
    /// every report, in place, so an open menu updates too.
    private var statusLines: [NSMenuItem] = []
    private(set) var environment = AppEnvironment.load()
    private lazy var monitor = ReadinessMonitor(environment: environment)

    private static let translateCombination = HotKeyCombination(
        keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey),
        displayName: "Control-Option-T")
    private static let correctCombination = HotKeyCombination(
        keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey),
        displayName: "Control-Option-C")
    private var hotKey: HotKey?
    private var correctHotKey: HotKey?
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        registerHotKeys()
        promptForAccessibilityIfNeeded()
        monitor.onChange = { [weak self] report in self?.render(report) }
        render(nil)
        monitor.start()
    }

    /// Registration stays non-exclusive. A failure is recorded as a fact and
    /// reaches the menu as a cause, never written over another line (#26).
    private func registerHotKeys() {
        let translate = Self.translateCombination
        hotKey = HotKey(keyCode: translate.keyCode, modifiers: translate.modifiers, id: 1) {
            [weak self] in self?.startAction(.translate)
        }
        let correct = Self.correctCombination
        correctHotKey = HotKey(keyCode: correct.keyCode, modifiers: correct.modifiers, id: 2) {
            [weak self] in self?.startAction(.correct)
        }
        monitor.hotKeys = [
            HotKeyFact(action: .translate, combination: translate, registered: hotKey != nil),
            HotKeyFact(action: .correct, combination: correct, registered: correctHotKey != nil),
        ]
    }

    private func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "\u{1F9A6}"
        item.button?.toolTip = "babelOtter"

        if let note = environment.configurationNote {
            configLine.title = "Configuration: \(note)"
            configLine.isHidden = false
        } else {
            configLine.isHidden = true
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(action(
            "Translate Selection (\(Self.translateCombination.displayName))",
            #selector(translateSelectionAction)))
        menu.addItem(action(
            "Correct Selection (\(Self.correctCombination.displayName))",
            #selector(correctSelectionAction)))
        menu.addItem(configLine)
        menu.addItem(.separator())
        menu.addItem(action("Check Again", #selector(refreshStatusAction)))
        menu.addItem(action("Open Configuration Folder", #selector(openConfiguration)))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit babelOtter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    /// The system prompt, at first launch only. Afterwards a missing grant is
    /// explained in the popup and the menu, never by a dialog (#28).
    private func promptForAccessibilityIfNeeded() {
        let key = "promptedForAccessibility"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard !AXIsProcessTrusted() else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @objc private func refreshStatusAction() { monitor.refresh() }

    @objc private func openAccessibilitySettings() { AccessibilitySettings.open() }

    func menuWillOpen(_ menu: NSMenu) { monitor.refresh() }

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
        guard let report else { return "babelOtter: checking" }
        guard let first = report.causes.first else { return "babelOtter: ready" }
        return "babelOtter: \(headline(report).lowercased()). \(first.detail)"
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
        var index = menu.index(of: configLine)
        for item in statusLines {
            menu.insertItem(item, at: index)
            index += 1
        }
    }

    private func makeStatusLines(_ report: ReadinessReport?) -> [NSMenuItem] {
        var lines = [NSMenuItem(title: Self.headline(report), action: nil, keyEquivalent: "")]
        for cause in report?.causes ?? [] {
            lines.append(NSMenuItem(title: cause.detail, action: nil, keyEquivalent: ""))
        }
        if report?.causes.contains(.accessibilityMissing) == true {
            lines.append(action("Open Accessibility Settings\u{2026}", #selector(openAccessibilitySettings)))
        }
        return lines
    }

    @objc private func openConfiguration() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        NSWorkspace.shared.open(home.appending(path: "Library/Application Support/ch.babelotter"))
    }

    @objc private func translateSelectionAction() { startAction(.translate) }
    @objc private func correctSelectionAction() { startAction(.correct) }

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
            environment: environment,
            close: { [weak self] in self?.panel.dismiss() },
            reopen: { [weak self] model in
                guard let self else { return }
                self.currentModel = model
                self.panel.show(PopupView(model: model))
            })
        currentModel = model
        // Non-key: the clipboard tier's synthetic Command-C must still reach
        // the source application's own selection, not a key panel of ours.
        panel.show(PopupView(model: model), activate: false)

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

    /// No capture starts, so the panel may take focus at once: Return opens
    /// System Settings, Escape dismisses. A second press replaces this popup
    /// rather than stacking another.
    private func showAccessibilityNeeded(for action: Action) {
        currentModel?.dismiss()
        let model = PopupModel(
            action: action,
            environment: environment,
            close: { [weak self] in self?.panel.dismiss() },
            reopen: { [weak self] model in
                guard let self else { return }
                self.currentModel = model
                self.panel.show(PopupView(model: model))
            })
        model.requireAccessibility()
        currentModel = model
        panel.show(PopupView(model: model))
    }
}
