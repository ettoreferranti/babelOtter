import BabelOtterKit
import CoreGraphics
import Foundation

/// Synthetic Command-C and Command-V.
///
/// Posting these needs the Accessibility grant, which babelOtter already
/// requires for reading selections, so it adds no new permission.
struct SyntheticKeystrokes: KeystrokeSending {

    private static let keyC: CGKeyCode = 8
    private static let keyV: CGKeyCode = 9

    func copy() { post(Self.keyC) }
    func paste() { post(Self.keyV) }

    private func post(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
