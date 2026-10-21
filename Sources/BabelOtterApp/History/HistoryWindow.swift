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
        window.present()
    }

    /// A record was saved.
    func recorded() {
        guard isOpen else { return }
        model?.refresh()
    }

    /// Recording was turned on or off: the note above the list follows.
    func policyChanged() {
        guard isOpen else { return }
        model?.refresh()
    }

    /// Delete is the destructive default; Escape cancels.
    private func confirmClearAll(_ count: Int?, _ delete: @escaping @MainActor () -> Void) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = Self.clearQuestion(count)
        alert.informativeText = "This cannot be undone."
        let deleteButton = alert.addButton(withTitle: "Delete")
        deleteButton.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { delete() }
        }
    }

    private static func clearQuestion(_ count: Int?) -> String {
        guard let count else { return "Delete all records?" }
        if count == 1 { return "Delete the 1 record?" }
        return "Delete all \(count.formatted()) records?"
    }

    func windowWillClose(_ notification: Notification) {
        isOpen = false
    }

    /// A fresh list in the same window. The hosting controller is made once,
    /// so reopening keeps the window's size.
    private func open() {
        let browser = HistoryBrowser(store: recorder.store, unavailable: recorder.unavailableReason)
        let model = HistoryWindowModel(
            browser: browser, configuration: configuration,
            policyNote: { [unowned recorder] in recorder.policy.windowNote })
        model.confirmClearAll = { [weak self] count, delete in self?.confirmClearAll(count, delete) }
        model.onCleared = { [unowned recorder] in recorder.cleared() }
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

/// The History window: Command-F focuses the search field.
@MainActor
final class HistoryWindow: AppWindow {

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

    override func find() -> Bool {
        model?.focusSearch()
        return true
    }
}
