import AppKit

/// A view that takes every key while it listens: the settings window's
/// hotkey recorder (#61).
@MainActor
protocol KeyRecording: AnyObject {
    var isRecording: Bool { get }
    func record(_ event: NSEvent)
    func cancel()
}

/// A plain window that handles the keys a main menu would: lingoSwen has
/// none, so without this Command-W, Command-C and the rest do nothing
/// (#68). A recorder that is listening gets every key first, Command-W
/// included (#61).
@MainActor
class AppWindow: NSWindow {

    /// A click anywhere but the listening recorder stops it listening: a
    /// button does not take focus on macOS, so focus alone would not.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            if let recorder = firstResponder as? KeyRecording {
                if recorder.isRecording {
                    if let view = recorder as? NSView {
                        let point = view.convert(event.locationInWindow, from: nil)
                        if !view.bounds.contains(point) { recorder.cancel() }
                    }
                }
            }
        }
        super.sendEvent(event)
    }

    /// Command-F; false when the window has nothing to find.
    func find() -> Bool { false }

    /// Only Command, or Command-Shift for redo: Command-Option-W and the
    /// like pass on. A key nothing here handles goes to `super`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let recorder = firstResponder as? KeyRecording {
            if recorder.isRecording {
                recorder.record(event)
                return true
            }
        }
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
        case "f": return find()
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
