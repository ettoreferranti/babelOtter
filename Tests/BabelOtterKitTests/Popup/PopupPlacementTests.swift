import CoreGraphics
import Testing

@testable import BabelOtterKit

@Suite("The popup opens where the selection is, fully on screen")
struct PopupPlacementTests {

    /// A laptop with the menu bar, and a larger display to its right.
    static let laptop = PopupScreen(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950))
    static let external = PopupScreen(
        frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1055))
    static let screens = [laptop, external]
    static let size = CGSize(width: 440, height: 160)
    static let onLaptop = CGPoint(x: 100, y: 500)

    private func origin(_ anchor: PopupAnchor, pointer: CGPoint = onLaptop) -> CGPoint {
        PopupPlacement.origin(size: Self.size, anchor: anchor, pointer: pointer, screens: Self.screens)
    }

    @Test("with no anchor, below and right of the pointer, as before")
    func pointer() {
        #expect(origin(.pointer) == CGPoint(x: 112, y: 328))
    }

    @Test("with no anchor, kept inside the pointer's screen")
    func pointerAtTheEdge() {
        #expect(origin(.pointer, pointer: CGPoint(x: 1500, y: 100)) == CGPoint(x: 1064, y: 8))
    }

    @Test("a pointer off every screen falls back to the first")
    func pointerOffScreen() {
        #expect(origin(.pointer, pointer: CGPoint(x: -500, y: 500)) == CGPoint(x: 8, y: 328))
    }

    @Test("just below the selection, on the selection's screen, wherever the pointer is")
    func belowTheSelection() {
        let selection = CGRect(x: 2000, y: 600, width: 300, height: 20)
        #expect(origin(.selection(selection)) == CGPoint(x: 2000, y: 432))
    }

    @Test("above the selection when there is no room below")
    func aboveTheSelection() {
        let selection = CGRect(x: 2000, y: 50, width: 300, height: 20)
        #expect(origin(.selection(selection)) == CGPoint(x: 2000, y: 78))
    }

    @Test("a selection at the right edge keeps the popup on its screen")
    func selectionAtTheEdge() {
        let selection = CGRect(x: 3300, y: 600, width: 100, height: 20)
        #expect(origin(.selection(selection)) == CGPoint(x: 2984, y: 432))
    }

    @Test("a selection on no screen falls back to the pointer")
    func selectionOffScreen() {
        let selection = CGRect(x: 9000, y: 600, width: 100, height: 20)
        #expect(origin(.selection(selection)) == CGPoint(x: 112, y: 328))
    }

    @Test("a window on another screen than the pointer: near the top, centred on the window")
    func windowElsewhere() {
        let window = CGRect(x: 1600, y: 100, width: 1200, height: 900)
        #expect(origin(.window(window)) == CGPoint(x: 1980, y: 800))
    }

    @Test("a window on the pointer's screen: near the pointer, as before")
    func windowWithThePointer() {
        let window = CGRect(x: 1600, y: 100, width: 1200, height: 900)
        let pointer = CGPoint(x: 2000, y: 500)
        #expect(origin(.window(window), pointer: pointer) == CGPoint(x: 2012, y: 328))
    }

    @Test("a window on no screen falls back to the pointer")
    func windowOffScreen() {
        let window = CGRect(x: 9000, y: 100, width: 800, height: 600)
        #expect(origin(.window(window)) == CGPoint(x: 112, y: 328))
    }

    @Test("Accessibility's top-left coordinates become AppKit's bottom-left ones")
    func fromAccessibility() {
        let rect = CGRect(x: 2000, y: 100, width: 300, height: 20)
        #expect(
            PopupPlacement.appKitRect(fromAccessibility: rect, primaryScreenHeight: 982)
                == CGRect(x: 2000, y: 862, width: 300, height: 20))
    }
}
