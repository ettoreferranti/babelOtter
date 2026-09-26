import BabelOtterKit
import CoreGraphics
import Foundation

enum CaptureOutcome: Sendable {
    case captured(SelectionSnapshot)
    case refused(CaptureRefusal)
}

/// Accessibility tiers first, then the clipboard (architecture section 7).
///
/// Blocking -- the clipboard tier polls the pasteboard -- so call it off the
/// main thread.
struct SelectionCapturer: Sendable {

    let configuration: Configuration

    func capture(from application: SourceApplication) -> CaptureOutcome {
        let policy = CapturePolicy(configuration: configuration)
        let reader = AccessibilityReader(processIdentifier: application.processIdentifier)
        let accessibilityTiers = policy.allowedTiers.filter { !$0.usesPasteboard }

        if let hit = TierLadder().capture(from: reader, allowing: accessibilityTiers) {
            return checked(SelectionSnapshot(
                text: UserText(hit.text), tier: hit.tier, application: application))
        }
        guard policy.allowedTiers.contains(.clipboard) else {
            return .refused(policy.refusal(
                application: application.name, clipboardWouldHaveBeenTried: true))
        }

        waitForModifierRelease()
        let capture = ClipboardCapture(pasteboard: SystemPasteboard(), keystrokes: SyntheticKeystrokes())
        guard case .success(let text) = capture.capture() else {
            return .refused(.nothingSelected)
        }
        return checked(SelectionSnapshot(
            text: UserText(text), tier: .clipboard, application: application))
    }

    private func checked(_ snapshot: SelectionSnapshot) -> CaptureOutcome {
        if let refusal = ActionPrecondition.refusal(for: snapshot) { return .refused(refusal) }
        return .captured(snapshot)
    }

    /// The hotkey fires while Control and Option are still held. A synthetic
    /// Command-C posted then can arrive as Control-Option-Command-C, which
    /// copies nothing. Wait, briefly, for the hand to come off the keys.
    private func waitForModifierRelease(timeout: TimeInterval = 1.0) {
        let held: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if CGEventSource.flagsState(.combinedSessionState).intersection(held).isEmpty { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }
}
