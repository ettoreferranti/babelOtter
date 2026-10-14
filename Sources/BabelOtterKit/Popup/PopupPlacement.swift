import CoreGraphics

/// A display, in AppKit's coordinates: origin at the bottom left of the
/// primary display, y growing upward.
public struct PopupScreen: Sendable, Equatable {
    public let frame: CGRect
    /// Without the menu bar and the Dock.
    public let visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

/// What the popup is placed against, in AppKit's coordinates (#97).
public enum PopupAnchor: Sendable, Equatable {
    /// The selected text's bounds, where the application reports them.
    case selection(CGRect)
    /// The focused window, where it reports no bounds for the selection.
    case window(CGRect)
    /// Nothing reported: the mouse pointer.
    case pointer
}

/// Where the popup opens: by the selection, on the selection's display,
/// and always fully on screen.
public enum PopupPlacement {

    /// Kept clear of every screen edge.
    static let margin: CGFloat = 8
    /// Down and to the right of the pointer, so it does not cover it.
    static let pointerOffset: CGFloat = 12
    /// Below a window's top edge, clear of its title bar.
    static let windowInset: CGFloat = 40

    public static func origin(
        size: CGSize, anchor: PopupAnchor, pointer: CGPoint, screens: [PopupScreen]
    ) -> CGPoint {
        switch anchor {
        case .selection(let rect):
            if let screen = screen(containing: CGPoint(x: rect.midX, y: rect.midY), in: screens) {
                return belowOrAbove(rect, size: size, on: screen)
            }
        case .window(let rect):
            let pointerScreen = screen(containing: pointer, in: screens)
            if let screen = screen(containing: CGPoint(x: rect.midX, y: rect.midY), in: screens) {
                if pointerScreen != screen {
                    let top = CGPoint(x: rect.midX - size.width / 2, y: rect.maxY - size.height - windowInset)
                    return clamp(top, size: size, to: screen)
                }
            }
        case .pointer:
            break
        }
        return nearPointer(pointer, size: size, screens: screens)
    }

    /// Accessibility measures from the top left of the primary display, y
    /// growing downward; AppKit from its bottom left, y growing upward.
    public static func appKitRect(fromAccessibility rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX, y: primaryScreenHeight - rect.maxY,
            width: rect.width, height: rect.height)
    }

    private static func belowOrAbove(_ rect: CGRect, size: CGSize, on screen: PopupScreen) -> CGPoint {
        var origin = CGPoint(x: rect.minX, y: rect.minY - size.height - margin)
        if origin.y < screen.visibleFrame.minY + margin {
            origin.y = rect.maxY + margin
        }
        return clamp(origin, size: size, to: screen)
    }

    private static func nearPointer(_ pointer: CGPoint, size: CGSize, screens: [PopupScreen]) -> CGPoint {
        let origin = CGPoint(
            x: pointer.x + pointerOffset, y: pointer.y - size.height - pointerOffset)
        guard let screen = screen(containing: pointer, in: screens) ?? screens.first else {
            return origin
        }
        return clamp(origin, size: size, to: screen)
    }

    private static func screen(containing point: CGPoint, in screens: [PopupScreen]) -> PopupScreen? {
        for screen in screens where screen.frame.contains(point) {
            return screen
        }
        return nil
    }

    private static func clamp(_ origin: CGPoint, size: CGSize, to screen: PopupScreen) -> CGPoint {
        let visible = screen.visibleFrame
        return CGPoint(
            x: min(max(origin.x, visible.minX + margin), visible.maxX - size.width - margin),
            y: min(max(origin.y, visible.minY + margin), visible.maxY - size.height - margin))
    }
}
