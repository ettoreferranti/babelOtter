import AppKit
import BabelOtterKit
import SwiftUI

/// Opens the History window from the menu and keeps it current (#68).
///
/// One window, built on first use and kept. Each opening starts a fresh
/// list; choosing History... while it is open -- minimized included -- only
/// brings it forward.
@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {

    private let recorder: HistoryRecorder
    private let configuration: () -> Configuration
    private var window: HistoryWindow?
    private var hosting: NSHostingController<HistoryView>?
    private var model: HistoryWindowModel?
    /// From opening to `windowWillClose`; unlike `isVisible`, still true
    /// while the window is minimized.
    private var isOpen = false

    init(recorder: HistoryRecorder, configuration: @escaping () -> Configuration) {
        self.recorder = recorder
        self.configuration = configuration
    }

    func show() {
        if !isOpen { open() }
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        // An accessory app has to bring itself forward for a normal window.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// A record was saved.
    func recorded() {
        guard isOpen else { return }
        model?.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        isOpen = false
    }

    /// A fresh list in the same window. The hosting controller is made once,
    /// so reopening keeps the window's size.
    private func open() {
        let browser = HistoryBrowser(store: recorder.store, unavailable: recorder.unavailableReason)
        let model = HistoryWindowModel(browser: browser, configuration: configuration)
        self.model = model
        if let window, let hosting {
            hosting.rootView = HistoryView(model: model)
            window.model = model
        } else {
            let hosting = NSHostingController(rootView: HistoryView(model: model))
            let window = HistoryWindow(content: hosting)
            window.model = model
            window.delegate = self
            self.hosting = hosting
            self.window = window
        }
        isOpen = true
    }
}

/// A plain window that handles the keys a main menu would: lingoSwen has
/// none, so without this Command-W, Command-C and the rest do nothing.
@MainActor
final class HistoryWindow: NSWindow {

    weak var model: HistoryWindowModel?

    init(content: NSViewController) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: true)
        contentViewController = content
        setContentSize(NSSize(width: 820, height: 520))
        title = "History"
        minSize = NSSize(width: 600, height: 360)
        isReleasedWhenClosed = false
        center()
        setFrameAutosaveName("HistoryWindow")
    }

    /// Only Command, or Command-Shift for redo: Command-Option-W and the
    /// like pass on. A key nothing here handles goes to `super`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handle(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if flags == [.command, .shift] {
            if key == "z" { return perform(Selector(("redo:"))) }
            return false
        }
        guard flags == .command else { return false }
        switch key {
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
        case "z": return perform(Selector(("undo:")))
        default: return false
        }
    }

    private func perform(_ action: Selector) -> Bool {
        NSApp.sendAction(action, to: nil, from: self)
    }
}
