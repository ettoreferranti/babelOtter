import ApplicationServices
import BabelOtterKit
import Foundation

/// Reads a selection through the Accessibility API: tiers 1 and 2.
///
/// Lives in the app target rather than the kit because it cannot be unit-tested
/// at all -- it needs a granted permission and another application with text
/// selected in it. The *ladder* that decides which tier wins is pure and lives
/// in `BabelOtterKit`, where CI proves every ordering case against a fake. What
/// is here is deliberately the thinnest possible layer over the system calls.
///
/// Holds only a pid, so it stays `Sendable`: `AXUIElement` is a CoreFoundation
/// type with no such guarantee, and elements are created on demand instead of
/// stored.
struct AccessibilityReader: SelectionSource {

    let processIdentifier: pid_t

    func read(tier: CaptureTier) -> String? {
        guard let element = focusedElement() else { return nil }
        switch tier {
        case .accessibilityText:
            return selectedText(of: element)
        case .textMarkerRange:
            return markerSelection(of: element)
        case .clipboard:
            // Not this reader's tier. Returning nil lets the ladder fall
            // through to whatever handles the pasteboard.
            return nil
        }
    }

    /// The focused element, system-wide, falling back to asking the application
    /// directly.
    ///
    /// Measured 2026-09-20: some applications refuse one route and answer the
    /// other, so trying both is the difference between "this app exposes
    /// nothing" and "this route exposes nothing".
    private func focusedElement() -> AXUIElement? {
        var focused: AnyObject?
        if AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused)
            == .success, let raw = focused
        {
            return (raw as! AXUIElement)
        }

        var appFocused: AnyObject?
        if AXUIElementCopyAttributeValue(
            AXUIElementCreateApplication(processIdentifier),
            kAXFocusedUIElementAttribute as CFString, &appFocused) == .success,
            let raw = appFocused
        {
            return (raw as! AXUIElement)
        }
        return nil
    }

    /// Tier 1. Native AppKit text views.
    private func selectedText(of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    /// Tier 2. WebKit exposes the selection only through text markers: Safari
    /// and Mail return `noValue` for tier 1 and 213 characters through this.
    /// Without it they would be clipboard-only, which is both less private and
    /// less reliable than necessary.
    private func markerSelection(of element: AXUIElement) -> String? {
        var range: AnyObject?
        guard
            AXUIElementCopyAttributeValue(
                element, "AXSelectedTextMarkerRange" as CFString, &range) == .success,
            let markerRange = range
        else { return nil }

        var text: AnyObject?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element, "AXStringForTextMarkerRange" as CFString, markerRange, &text) == .success
        else { return nil }
        return text as? String
    }
}
