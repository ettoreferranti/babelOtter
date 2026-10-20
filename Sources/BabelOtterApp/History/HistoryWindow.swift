import AppKit
import BabelOtterKit
import SwiftUI

/// Opens the History window from the menu and keeps it current (#68).
///
/// One window, built on first use and kept. Each opening starts a fresh
/// list; choosing History... while it is open only brings it forward.
@MainActor
final class HistoryWindowController {

    private let recorder: HistoryRecorder
    private let configuration: () -> Configuration
    private var window: HistoryWindow?
    private var model: HistoryWindowModel?

    init(recorder: HistoryRecorder, configuration: @escaping () -> Configuration) {
        self.recorder = recorder
        self.configuration = configuration
    }

    func show() {
        let window = self.window ?? HistoryWindow()
        self.window = window
        if !window.isVisible {
            let browser = HistoryBrowser(store: recorder.store, unavailable: recorder.problem)
            let model = HistoryWindowModel(browser: browser, configuration: configuration)
            self.model = model
            window.model = model
            window.contentViewController = NSHostingController(rootView: HistoryView(model: model))
        }
        // An accessory app has to bring itself forward for a normal window.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// A record was saved.
    func recorded() {
        guard let window, window.isVisible else { return }
        model?.refresh()
    }
}

/// A plain window that handles the keys a main menu would: lingoSwen has
/// none, so without this Command-W, Command-C and the rest do nothing.
@MainActor
final class HistoryWindow: NSWindow {

    weak var model: HistoryWindowModel?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: true)
        title = "History"
        minSize = NSSize(width: 600, height: 360)
        isReleasedWhenClosed = false
        center()
        setFrameAutosaveName("HistoryWindow")
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        let shifted = flags.contains(.shift)
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w":
            performClose(nil)
            return true
        case "f":
            model?.focusSearch()
            return true
        case "c": return perform(#selector(NSText.copy(_:)))
        case "v": return perform(#selector(NSText.paste(_:)))
        case "x": return perform(#selector(NSText.cut(_:)))
        case "a": return perform(#selector(NSResponder.selectAll(_:)))
        case "z": return perform(Selector(shifted ? "redo:" : "undo:"))
        default: return super.performKeyEquivalent(with: event)
        }
    }

    private func perform(_ action: Selector) -> Bool {
        NSApp.sendAction(action, to: nil, from: self)
    }
}
