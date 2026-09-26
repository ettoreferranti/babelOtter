import AppKit
import SwiftUI

/// A floating panel that takes keyboard focus without activating babelOtter,
/// so the application the text came from stays frontmost (spec M1b,
/// "non-activating popup").
@MainActor
final class PopupPanel: NSPanel {

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 160),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: true)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    /// Shows `content` near the cursor. `activate` defaults to true for the
    /// common case (choosing a direction, a finished translation reopened
    /// after Replace); pass `false` for the moment capture starts, when a
    /// synthetic Command-C must still reach the source application rather
    /// than this panel -- see `makeKeyNow()`.
    func show<Content: View>(_ content: Content, activate: Bool = true) {
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = [.preferredContentSize]
        contentViewController = controller
        placeNearCursor()
        orderFrontRegardless()
        if activate { makeKey() }
    }

    /// Grants keyboard focus to a panel already on screen. Called once
    /// capture has finished reading the selection, so the synthetic
    /// Command-C the clipboard tier may have posted was routed to the source
    /// application, not to this panel (spec M1b, "non-activating popup").
    func makeKeyNow() {
        makeKey()
    }

    func dismiss() {
        orderOut(nil)
        contentViewController = nil
    }

    private func placeNearCursor() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = frame.size
        var origin = NSPoint(x: mouse.x + 12, y: mouse.y - size.height - 12)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        setFrameOrigin(origin)
    }
}
