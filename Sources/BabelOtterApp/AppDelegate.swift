import AppKit
import ApplicationServices
import BabelOtterKit

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
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
}
