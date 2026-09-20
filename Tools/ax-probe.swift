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
import CoreGraphics
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

/// Which application currently owns the frontmost window.
///
/// Deliberately NOT `NSWorkspace.shared.frontmostApplication`. That property is
/// updated through workspace notifications, which need a running run loop, and
/// this is a command-line tool that never starts one. Measured on 2026-09-20:
/// with the frontmost app switched from Finder to a terminal mid-run,
/// `NSWorkspace` kept reporting Finder for the whole eight seconds while the
/// window list tracked the change immediately. That is why the first version of
/// this probe reported the launching terminal for all six rounds, and why the
/// second version waited forever for a switch it could not see.
///
/// The window list needs no run loop and no extra permission: owner name and
/// owner pid are available without Screen Recording, which only gates window
/// *titles*.
struct Frontmost {
    let pid: pid_t
    let label: String
}

func frontmost() -> Frontmost? {
    guard
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else { return nil }

    for window in windows {
        guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
            let name = window[kCGWindowOwnerName as String] as? String,
            let pid = window[kCGWindowOwnerPID as String] as? pid_t
        else { continue }
        let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        return Frontmost(pid: pid, label: "\(name)  [\(bundle ?? "?")]")
    }
    return nil
}

/// The terminal this was launched from: whatever is in front when we start.
let host = frontmost()

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

/// The focused element, system-wide, falling back to asking the app by pid.
///
/// The system-wide element answers for whichever app has focus, but some apps
/// refuse it while still answering when addressed directly. Trying both is what
/// separates "this app exposes nothing" from "this route exposes nothing".
func focusedElement(pid: pid_t) -> (AXUIElement?, String) {
    var focused: AnyObject?
    let systemError = AXUIElementCopyAttributeValue(
        AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &focused)
    if systemError == .success, let raw = focused {
        return ((raw as! AXUIElement), "system-wide")
    }

    var appFocused: AnyObject?
    let appError = AXUIElementCopyAttributeValue(
        AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &appFocused)
    if appError == .success, let raw = appFocused {
        return ((raw as! AXUIElement), "per-application")
    }
    return (nil, "system-wide \(name(systemError)); per-application \(name(appError))")
}

/// Blocks until an app other than the launching terminal is frontmost and has
/// settled, printing what it can see while it waits.
///
/// The heartbeat is not decoration. When this waited on a source that never
/// updated, it sat silent and looked hung; printing what it currently sees
/// would have shown the cause in seconds.
func waitForForeignApp(timeout: TimeInterval = 180) -> Frontmost? {
    let deadline = Date().addingTimeInterval(timeout)
    var lastBeat = Date.distantPast
    while Date() < deadline {
        if let current = frontmost(), current.pid != host?.pid {
            Thread.sleep(forTimeInterval: 2.0)
            if let settled = frontmost(), settled.pid == current.pid { return settled }
            continue
        }
        if Date().timeIntervalSince(lastBeat) > 4 {
            print("  waiting for you to switch away... (frontmost now: \(frontmost()?.label ?? "unknown"))")
            lastBeat = Date()
        }
        Thread.sleep(forTimeInterval: 0.3)
    }
    return nil
}

/// Blocks until the launching terminal is frontmost again.
func waitForReturnHome(timeout: TimeInterval = 180) {
    let deadline = Date().addingTimeInterval(timeout)
    var lastBeat = Date.distantPast
    while Date() < deadline {
        if frontmost()?.pid == host?.pid { return }
        if Date().timeIntervalSince(lastBeat) > 4 {
            print("  waiting for you to come back... (frontmost now: \(frontmost()?.label ?? "unknown"))")
            lastBeat = Date()
        }
        Thread.sleep(forTimeInterval: 0.3)
    }
}

print("=== 3. Accessibility grant, live ===")
print("AXIsProcessTrusted: \(AXIsProcessTrusted() ? "YES" : "NO")")

guard AXIsProcessTrusted() else {
    print("")
    print("NOT TRUSTED YET. Grant Accessibility to this terminal:")
    print("  System Settings > Privacy & Security > Accessibility > +")
    print("  (add \(frontmost()?.label ?? "this terminal"))")
    print("Then QUIT it completely (Cmd-Q), reopen it, and rerun this script.")
    print("")
    print("If the + button is greyed out, or the toggle refuses to stay on, that is")
    print("the MDM answer - report it verbatim, it means M1b's premise fails.")
    exit(1)
}

print("")
print("Trusted. This terminal is \(host?.label ?? "unknown").")
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

    let (element, route) = focusedElement(pid: app.pid)
    print("  app:    \(app.label)")
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
