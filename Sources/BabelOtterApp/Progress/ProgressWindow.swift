import AppKit
import BabelOtterKit
import SwiftUI

/// Opens the Progress window from the menu (#78). One window, built on
/// first use and kept; each opening reads History again, and so does every
/// saved record while it is open.
@MainActor
final class ProgressWindowController: NSObject, NSWindowDelegate {

    private let model: ProgressModel
    private var window: AppWindow?
    private var isOpen = false

    init(model: ProgressModel) {
        self.model = model
    }

    func show() {
        model.refresh()
        if window == nil { window = makeWindow() }
        isOpen = true
        window?.present()
    }

    /// A record was saved, pruned or cleared.
    func recorded() {
        guard isOpen else { return }
        model.refresh()
    }

    /// Coming back from History after Clear All shows it at once.
    func windowDidBecomeKey(_ notification: Notification) {
        model.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        isOpen = false
    }

    private func makeWindow() -> AppWindow {
        let hosting = NSHostingController(rootView: ProgressReportView(model: model))
        let window = AppWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: true)
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 760, height: 560))
        window.title = "Progress"
        window.minSize = NSSize(width: 560, height: 360)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("ProgressWindow")
        return window
    }
}
