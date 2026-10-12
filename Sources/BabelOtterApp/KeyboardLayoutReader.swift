import BabelOtterKit
import Carbon.HIToolbox
import Foundation

/// What each key types on the keyboard layout in use, and when that layout
/// changes (#26).
@MainActor
final class KeyboardLayoutReader: NSObject {

    var onChange: (@MainActor () -> Void)?

    /// `.deliverImmediately`: babelOtter is an accessory app that is almost
    /// never active, and distributed notifications are otherwise held back
    /// while an app is inactive -- the hotkeys would stay on the old layout
    /// until babelOtter happened to be activated.
    func start() {
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(layoutDidChange),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, suspensionBehavior: .deliverImmediately)
    }

    @objc private func layoutDidChange(_ notification: Notification) {
        onChange?()
    }

    /// The current layout; the ASCII-capable one when the current input
    /// source has no key layout (Japanese or Chinese input methods); the US
    /// letters when macOS reports neither.
    static func current() -> KeyLayout {
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() {
            if let characters = characters(of: source) {
                return KeyLayout(characters: characters)
            }
        }
        if let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() {
            if let characters = characters(of: source) {
                return KeyLayout(characters: characters)
            }
        }
        return KeyLayout.usANSI
    }

    /// Key codes 0-127 with no modifiers. Keys that type nothing visible
    /// (function keys, dead keys) are left out. Read while `source` is alive,
    /// because the layout data belongs to it.
    private static func characters(of source: TISInputSource) -> [UInt32: String]? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var characters: [UInt32: String] = [:]
        for code in UInt16(0)..<128 {
            var deadKeyState: UInt32 = 0
            var length = 0
            var buffer = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
                buffer.count, &length, &buffer)
            guard status == noErr, length > 0 else { continue }
            let typed = String(utf16CodeUnits: buffer, count: length)
            let visible = typed.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
            guard !visible.isEmpty else { continue }
            characters[UInt32(code)] = typed
        }
        return characters
    }
}
