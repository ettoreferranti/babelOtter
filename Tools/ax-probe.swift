// Does this Mac permit the Accessibility grant, and does the grant yield text?
//
// A diagnostic, not shipped code. It answers the question docs/architecture.md
// section 7 lists as unmeasured -- whether a managed Mac permits the
// Accessibility grant at all -- and, for each app tried, which of the three
// capture tiers actually works there.
//
// Deliberately outside Sources/, so it is not a SwiftPM target and none of the
// architecture guards scan it. Run it through Tools/ax-probe.sh.

import AppKit
import ApplicationServices
import Foundation

// Unbuffered stdout. This probe spends most of its life blocked waiting for
// the reader to switch apps, and its output goes through `tee`, so stdout is a
// pipe rather than a terminal. C stdio block-buffers a pipe, which meant every
// prompt sat in a 4KB buffer until the process exited -- the script looked like
// it had hung after step 2, when in fact it was waiting and saying so into a
// buffer nobody could see. The shell's own `echo`s appeared throughout,
// because bash writes those straight out, which made it look like the Swift
// half had never started.
setvbuf(stdout, nil, _IONBF, 0)

let rounds = Int(CommandLine.arguments.dropFirst().first ?? "6") ?? 6

/// The terminal this was launched from. Readings are taken in *other* apps, so
/// this is the app whose return to the front means "ready for the next one".
let host = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

func describe(_ app: NSRunningApplication?) -> String {
    guard let app else { return "unknown" }
    return "\(app.localizedName ?? "?")  [\(app.bundleIdentifier ?? "?")]"
}

/// AXError by name. `-25204` tells you nothing; `cannotComplete` tells you the
/// app never answered, which is a different problem from `attributeUnsupported`.
func name(_ error: AXError) -> String {
    switch error {
    case .success: return "success"
    case .failure: return "failure"
    case .illegalArgument: return "illegalArgument"
    case .invalidUIElement: return "invalidUIElement"
    case .invalidUIElementObserver: return "invalidUIElementObserver"
    case .cannotComplete: return "cannotComplete (the app did not answer)"
    case .attributeUnsupported: return "attributeUnsupported"
    case .actionUnsupported: return "actionUnsupported"
    case .notificationUnsupported: return "notificationUnsupported"
    case .notImplemented: return "notImplemented"
    case .notificationAlreadyRegistered: return "notificationAlreadyRegistered"
    case .notificationNotRegistered: return "notificationNotRegistered"
    case .apiDisabled: return "apiDisabled (Accessibility not granted)"
    case .noValue: return "noValue (nothing selected, or not exposed)"
    case .parameterizedAttributeUnsupported: return "parameterizedAttributeUnsupported"
    case .notEnoughPrecision: return "notEnoughPrecision"
    @unknown default: return "unknown(\(error.rawValue))"
    }
}

func string(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
    else { return nil }
    return value as? String
}

/// Tier 1: kAXSelectedTextAttribute. Native AppKit text views.
func tier1(_ element: AXUIElement) -> String {
    var value: AnyObject?
    let error = AXUIElementCopyAttributeValue(
        element, kAXSelectedTextAttribute as CFString, &value)
    guard error == .success else { return "unavailable - \(name(error))" }
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
        return "unavailable - \(name(rangeError))"
    }
    var text: AnyObject?
    let textError = AXUIElementCopyParameterizedAttributeValue(
        element, "AXStringForTextMarkerRange" as CFString, markerRange, &text)
    guard textError == .success else { return "range, but no string - \(name(textError))" }
    guard let string = text as? String, !string.isEmpty else { return "EMPTY" }
    return "OK - \(string.count) chars"
}

/// The focused element, system-wide, falling back to asking the app directly.
///
/// The system-wide element answers for whichever app has focus, but some apps
/// refuse it while still answering when addressed by pid. Trying both is what
/// separates "this app exposes nothing" from "this route exposes nothing".
func focusedElement(in app: NSRunningApplication) -> (AXUIElement?, String) {
    var focused: AnyObject?
    let systemError = AXUIElementCopyAttributeValue(
        AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused)
    if systemError == .success, let raw = focused {
        return ((raw as! AXUIElement), "system-wide")
    }

    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    var appFocused: AnyObject?
    let appError = AXUIElementCopyAttributeValue(
        appElement, kAXFocusedUIElementAttribute as CFString, &appFocused)
    if appError == .success, let raw = appFocused {
        return ((raw as! AXUIElement), "per-application")
    }
    return (nil, "system-wide \(name(systemError)); per-application \(name(appError))")
}

/// Blocks until some app other than the launching terminal is frontmost and has
/// stayed there long enough for a selection to exist.
///
/// This replaces a fixed countdown. The countdown assumed the reader would
/// switch apps on the probe's schedule; in practice the terminal stayed
/// frontmost for all six rounds and every reading was of the terminal itself.
func waitForForeignApp(timeout: TimeInterval = 120) -> NSRunningApplication? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        guard let app = NSWorkspace.shared.frontmostApplication,
            app.bundleIdentifier != host
        else {
            Thread.sleep(forTimeInterval: 0.3)
            continue
        }
        // Let the switch settle, then confirm we are still there. Guards
        // against reading mid-transition through an app launcher.
        Thread.sleep(forTimeInterval: 2.0)
        if let settled = NSWorkspace.shared.frontmostApplication,
            settled.bundleIdentifier == app.bundleIdentifier
        {
            return settled
        }
    }
    return nil
}

/// Blocks until the launching terminal is frontmost again.
func waitForReturnHome(timeout: TimeInterval = 120) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == host { return }
        Thread.sleep(forTimeInterval: 0.3)
    }
}

print("=== 3. Accessibility grant, live ===")
print("AXIsProcessTrusted: \(AXIsProcessTrusted() ? "YES" : "NO")")

guard AXIsProcessTrusted() else {
    print("")
    print("NOT TRUSTED YET. Grant Accessibility to this terminal:")
    print("  System Settings > Privacy & Security > Accessibility > +")
    print("  (add \(describe(NSWorkspace.shared.frontmostApplication)))")
    print("Then QUIT it completely (Cmd-Q), reopen it, and rerun this script.")
    print("")
    print("If the + button is greyed out, or the toggle refuses to stay on, that is")
    print("the MDM answer - report it verbatim, it means M1b's premise fails.")
    exit(1)
}

print("")
print("Trusted. This terminal is \(describe(NSWorkspace.shared.frontmostApplication)).")
print("")
print("It waits for you, so there is no countdown to race:")
print("  1. Switch to an app and SELECT SOME TEXT.")
print("  2. It reads ~2s after the switch settles, then asks you to come back.")
print("  3. Switch back here, and it sets up the next round.")
print("")
print("Worth covering: TextEdit, Safari, Outlook, Teams, Word, VS Code.")
print("A terminal cannot be measured this way - it is the one app that is never")
print("in front when a reading is taken.")

for round in 1...rounds {
    print("")
    print("--- round \(round)/\(rounds): switch to an app and select text ---")

    guard let app = waitForForeignApp() else {
        print("  no app came forward within the timeout; stopping.")
        break
    }

    let (element, route) = focusedElement(in: app)
    print("  app:    \(describe(app))")
    guard let element else {
        print("  focused element: NONE (\(route))")
        print("  -> tier 3 only: this app exposes no focused element at all")
        print("  ...switch back to the terminal for the next round")
        waitForReturnHome()
        continue
    }

    print("  route:  \(route)")
    print("  role:   \(string(element, kAXRoleAttribute as String) ?? "?")")
    print("  tier 1: \(tier1(element))")
    print("  tier 2: \(tier2(element))")
    print("  ...switch back to the terminal for the next round")
    waitForReturnHome()
}

print("")
print("=== what the results mean ===")
print("  tier 1 OK                       -> native AppKit text, the easy case")
print("  tier 1 EMPTY/absent, tier 2 OK  -> WebKit, needs the text-marker path")
print("  both EMPTY or absent            -> clipboard-only (Electron), what #77 closes")
