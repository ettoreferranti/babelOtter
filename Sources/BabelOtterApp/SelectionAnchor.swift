import AppKit
import ApplicationServices
import BabelOtterKit

/// Where the selection is on screen, asked of Accessibility just before the
/// popup shows, so it opens on the selection's display (#97).
///
/// Every call is capped at `timeout`: the popup appears the moment the hotkey
/// is pressed, and a busy application must not hold it back. Anything the
/// application does not answer falls back a step -- the selection's bounds,
/// then the focused window, then the pointer -- and `PopupPlacement` decides
/// the rest.
struct SelectionAnchor {

    let processIdentifier: pid_t

    static let timeout: Float = 0.1

    @MainActor
    func read() -> PopupAnchor {
        guard let primary = NSScreen.screens.first else { return .pointer }
        let height = primary.frame.height
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, Self.timeout)
        if let focused = element(application, kAXFocusedUIElementAttribute),
            let bounds = selectionBounds(of: focused)
        {
            return .selection(PopupPlacement.appKitRect(fromAccessibility: bounds, primaryScreenHeight: height))
        }
        if let window = element(application, kAXFocusedWindowAttribute), let frame = frame(of: window) {
            return .window(PopupPlacement.appKitRect(fromAccessibility: frame, primaryScreenHeight: height))
        }
        return .pointer
    }

    private func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
            let raw = value, CFGetTypeID(raw) == AXUIElementGetTypeID()
        else { return nil }
        let element = raw as! AXUIElement
        AXUIElementSetMessagingTimeout(element, Self.timeout)
        return element
    }

    /// Native text views report the selected range's bounds; WebKit (Safari,
    /// Mail) only a text marker range's. A zero-height answer means the
    /// application has none to give.
    private func selectionBounds(of element: AXUIElement) -> CGRect? {
        var range: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
            let range,
            let bounds = parameterizedRect(element, kAXBoundsForRangeParameterizedAttribute, range)
        {
            return bounds
        }
        var markers: AnyObject?
        if AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &markers) == .success,
            let markers,
            let bounds = parameterizedRect(element, "AXBoundsForTextMarkerRange", markers)
        {
            return bounds
        }
        return nil
    }

    private func parameterizedRect(_ element: AXUIElement, _ attribute: String, _ parameter: AnyObject) -> CGRect? {
        var value: AnyObject?
        guard
            AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value)
                == .success,
            let rect = rectValue(value), rect.height > 0
        else { return nil }
        return rect
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        var position: AnyObject?
        var size: AnyObject?
        guard
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
            let origin = pointValue(position),
            let extent = sizeValue(size),
            extent.height > 0
        else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    private func rectValue(_ value: AnyObject?) -> CGRect? {
        var rect = CGRect.zero
        guard let value = axValue(value), AXValueGetValue(value, .cgRect, &rect) else { return nil }
        return rect
    }

    private func pointValue(_ value: AnyObject?) -> CGPoint? {
        var point = CGPoint.zero
        guard let value = axValue(value), AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private func sizeValue(_ value: AnyObject?) -> CGSize? {
        var size = CGSize.zero
        guard let value = axValue(value), AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private func axValue(_ value: AnyObject?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
