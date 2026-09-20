// Does this Mac permit the Accessibility grant, and does the grant yield text?
//
// A diagnostic, not shipped code. It answers the question docs/architecture.md
// section 7 lists as unmeasured -- "whether a managed ZHAW Mac permits the
// Accessibility grant at all" -- and, for each app tried, which of the three
// capture tiers actually works there.
//
// Deliberately outside Sources/, so it is not a SwiftPM target and none of the
// architecture guards scan it. Run it through Tools/ax-probe.sh.

import AppKit
import ApplicationServices
import Foundation

let rounds = Int(CommandLine.arguments.dropFirst().first ?? "6") ?? 6
let pause = 7.0

func frontmost() -> String {
    guard let app = NSWorkspace.shared.frontmostApplication else { return "unknown" }
    return "\(app.localizedName ?? "?")  [\(app.bundleIdentifier ?? "?")]"
}

func string(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
    else { return nil }
    return value as? String
}

/// Tier 1: kAXSelectedTextAttribute. Works in native AppKit text views.
func tier1(_ element: AXUIElement) -> String {
    var value: AnyObject?
    let err = AXUIElementCopyAttributeValue(
        element, kAXSelectedTextAttribute as CFString, &value)
    guard err == .success else { return "unavailable (AXError \(err.rawValue))" }
    guard let text = value as? String, !text.isEmpty else { return "EMPTY" }
    return "OK - \(text.count) chars"
}

/// Tier 2: WebKit's text markers. Safari and Mail's HTML view return noValue
/// for tier 1 and expose the selection only through these.
func tier2(_ element: AXUIElement) -> String {
    var range: AnyObject?
    let rangeError = AXUIElementCopyAttributeValue(
        element, "AXSelectedTextMarkerRange" as CFString, &range)
    guard rangeError == .success, let markerRange = range else {
        return "unavailable (AXError \(rangeError.rawValue))"
    }
    var text: AnyObject?
    let textError = AXUIElementCopyParameterizedAttributeValue(
        element, "AXStringForTextMarkerRange" as CFString, markerRange, &text)
    guard textError == .success else {
        return "range, but no string (AXError \(textError.rawValue))"
    }
    guard let string = text as? String, !string.isEmpty else { return "EMPTY" }
    return "OK - \(string.count) chars"
}

print("=== 3. Accessibility grant, live ===")
print("AXIsProcessTrusted: \(AXIsProcessTrusted() ? "YES" : "NO")")

guard AXIsProcessTrusted() else {
    print("")
    print("NOT TRUSTED YET. Grant Accessibility to Terminal:")
    print("  System Settings > Privacy & Security > Accessibility > +   (add Terminal)")
    print("Then QUIT Terminal completely (Cmd-Q), reopen it, and rerun this script.")
    print("")
    print("If the + button is greyed out, or the toggle refuses to stay on, that is")
    print("the MDM answer - report it verbatim, it means M1b's premise fails.")
    exit(1)
}

print("")
print("Trusted. Now \(rounds) rounds, \(Int(pause))s apart.")
print("Each round: switch to an app, SELECT SOME TEXT, then wait for the reading.")
print("Suggested order - TextEdit, Safari, Outlook, Teams, Word, VS Code.")

for round in 1...rounds {
    print("")
    print("--- round \(round)/\(rounds): select text now, reading in \(Int(pause))s ---")
    Thread.sleep(forTimeInterval: pause)

    var focused: AnyObject?
    let err = AXUIElementCopyAttributeValue(
        AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused)
    print("  app:    \(frontmost())")
    guard err == .success, let raw = focused else {
        print("  focused element: NONE (AXError \(err.rawValue))")
        continue
    }
    let element = raw as! AXUIElement
    print("  role:   \(string(element, kAXRoleAttribute as String) ?? "?")")
    print("  tier 1: \(tier1(element))")
    print("  tier 2: \(tier2(element))")
}

print("")
print("=== what the results mean ===")
print("  tier 1 OK                       -> native AppKit text, the easy case")
print("  tier 1 EMPTY/absent, tier 2 OK  -> WebKit, needs the text-marker path")
print("  both EMPTY or absent            -> clipboard-only (Electron), what #77 closes")
