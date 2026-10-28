import AppKit
import BabelOtterKit
import SwiftUI

/// Opens the scratchpad from the menu (#84). One window, built on first use
/// and kept: closing only hides it, so the text is still there next time,
/// until lingoSwen quits.
@MainActor
final class ScratchpadWindowController {

    let model: ScratchpadModel
    private var window: AppWindow?

    init(model: ScratchpadModel) {
        self.model = model
    }

    func show() {
        if window == nil { window = makeWindow() }
        window?.present()
    }

    private func makeWindow() -> AppWindow {
        let hosting = NSHostingController(rootView: ScratchpadView(model: model))
        let window = AppWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: true)
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 900, height: 560))
        window.title = "Scratchpad"
        window.minSize = NSSize(width: 640, height: 380)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("ScratchpadWindow")
        return window
    }
}
