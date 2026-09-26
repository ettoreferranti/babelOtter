import AppKit
import ApplicationServices
import BabelOtterKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private let ollamaLine = NSMenuItem(title: "Ollama: checking...", action: nil, keyEquivalent: "")
    private let accessLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    /// Hidden unless `environment.configurationNote` has something to say --
    /// most launches have nothing wrong with the config file, and a menu
    /// line reporting that would be noise.
    private let configLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private(set) var environment = AppEnvironment.load()
    private var hotKey: HotKey?
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
        hotKey = HotKey(
            keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey), id: 1
        ) { [weak self] in self?.translateSelection() }
        if hotKey == nil { ollamaLine.title = "Control-Option-T is taken by another app" }
        promptForAccessibilityIfNeeded()
        refreshStatus()
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
        menu.addItem(action("Translate Selection (Control-Option-T)", #selector(translateSelectionAction)))
        menu.addItem(ollamaLine)
        menu.addItem(accessLine)
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

    /// Shows the system prompt once; the grant itself happens in System Settings.
    private func promptForAccessibilityIfNeeded() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @objc private func refreshStatusAction() { refreshStatus() }

    func refreshStatus() {
        accessLine.title = AXIsProcessTrusted()
            ? "Accessibility: granted"
            : "Accessibility: not granted (System Settings > Privacy & Security)"
        let client = environment.client
        let model = environment.configuration.models[.translate] ?? Configuration.defaultModel
        Task {
            let status = await client.health(configuredModel: model)
            ollamaLine.title = "Ollama: \(status.detail)"
        }
    }

    @objc private func openConfiguration() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        NSWorkspace.shared.open(home.appending(path: "Library/Application Support/ch.babelotter"))
    }

    @objc private func translateSelectionAction() { translateSelection() }

    /// Captures the frontmost application's selection and streams a
    /// translation into the popup (NFR-P3/P5: never the text itself, outside
    /// the popup's own view and the clipboard on Copy).
    ///
    /// While a capture is already in flight, a fresh press is ignored
    /// outright -- the capture is left to run to its own restore rather than
    /// being raced or cancelled. Only once no capture is in flight does a
    /// second press dismiss (and so cancel) the current popup before
    /// starting a new one.
    func translateSelection() {
        guard AXIsProcessTrusted() else {
            promptForAccessibilityIfNeeded()
            return
        }
        guard !isCapturing else { return }
        guard let front = NSWorkspace.shared.frontmostApplication,
            front.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        let source = SourceApplication(
            processIdentifier: front.processIdentifier,
            bundleIdentifier: front.bundleIdentifier,
            name: front.localizedName ?? "this application")

        currentModel?.dismiss()

        let model = PopupModel(
            environment: environment,
            close: { [weak self] in self?.panel.dismiss() },
            reopen: { [weak self] in
                guard let self, let model = self.currentModel else { return }
                self.panel.show(PopupView(model: model))
            })
        currentModel = model
        panel.show(PopupView(model: model))

        isCapturing = true
        let capturer = SelectionCapturer(configuration: environment.configuration)
        Task {
            let outcome = await Task.detached { capturer.capture(from: source) }.value
            isCapturing = false
            // A stale result -- from a capture whose popup is no longer the
            // current one -- must never land in a newer popup.
            guard currentModel === model else { return }
            model.begin(with: outcome)
        }
    }
}
