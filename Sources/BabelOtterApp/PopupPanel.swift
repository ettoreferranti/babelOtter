import AppKit
import BabelOtterKit
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

    /// What the last placement used, so a popup reopened after Replace
    /// returns to the same place.
    private var anchor: PopupAnchor = .pointer

    /// Shows `content` by `anchor` -- the selection, its window or the
    /// pointer (#97) -- or, when nil, where the last popup was anchored.
    /// `activate` defaults to true for the
    /// common case (choosing a direction, a finished translation reopened
    /// after Replace); pass `false` for the moment capture starts, when a
    /// synthetic Command-C must still reach the source application rather
    /// than this panel -- see `makeKeyNow()`.
    func show<Content: View>(_ content: Content, activate: Bool = true, anchor: PopupAnchor? = nil) {
        if let anchor { self.anchor = anchor }
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = [.preferredContentSize]
        contentViewController = controller
        place()
        orderFrontRegardless()
        if activate { makeKey() }
    }

    /// Grants keyboard focus to a panel already on screen. Called once
    /// capture has finished reading the selection, so the synthetic
    /// Command-C the clipboard tier may have posted was routed to the source
    /// application, not to this panel (spec M1b, "non-activating popup").
    ///
    /// Does nothing once the panel is hidden: a popup dismissed during the
    /// capture has been ordered out, and making an invisible window key
    /// would take the user's keystrokes away from the application they are
    /// typing in.
    func makeKeyNow() {
        guard isVisible else { return }
        makeKey()
    }

    func dismiss() {
        orderOut(nil)
        contentViewController = nil
    }

    private func place() {
        let screens = NSScreen.screens.map {
            PopupScreen(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        setFrameOrigin(PopupPlacement.origin(
            size: frame.size, anchor: anchor, pointer: NSEvent.mouseLocation, screens: screens))
    }
}
