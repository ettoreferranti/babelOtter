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

let arguments = Array(CommandLine.arguments.dropFirst())
let writeMode = arguments.contains("--write")
let rounds = Int(arguments.first { Int($0) != nil } ?? "6") ?? 6

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

/// Switches on Chromium's accessibility tree before reading.
///
/// Electron apps keep it off until an assistive tool asks. Setting
/// AXManualAccessibility returns success immediately, but the tree is built
/// asynchronously, so the first read afterwards is expected to fail -- which is
/// why architecture.md section 7 says this must be set when an app is first
/// seen frontmost, not at capture time.
///
/// Without it, an Electron app reports `noValue` for the focused element and
/// looks permanently unreachable. That is what the 2026-09-20 run measured for
/// VS Code and Teams, and it is exactly the conclusion the first prototype drew
/// before the spike corrected it.
///
/// Note this switches on accessibility work inside applications we do not own.
/// That is ordinary behaviour for assistive software -- it is what VoiceOver
/// does -- but it is a side effect worth stating rather than burying.
func enableManualAccessibility(pid: pid_t) -> String {
    let error = AXUIElementSetAttributeValue(
        AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
    return name(error)
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

/// Looks for a descendant that does expose a selection.
///
/// Measured 2026-09-20: in Outlook, Teams, Word and OneNote the *focused*
/// element is a container -- AXWindow, AXSplitGroup, AXScrollArea -- which
/// supports neither selection attribute. That does not prove the text is
/// unreachable; it proves the focused element is not the text. Walking down
/// tells us which of those it is, and that is the difference between "needs a
/// smarter tier 1" and "genuinely clipboard-only".
///
/// Breadth-first and budgeted, because an accessibility tree can be large and
/// this runs while the reader waits.
func descendantWithSelection(
    _ root: AXUIElement, budget: Int = 400
) -> (role: String, tier1: String, tier2: String, depth: Int)? {
    var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
    var visited = 0

    while queue.isEmpty == false, visited < budget {
        let (element, depth) = queue.removeFirst()
        visited += 1

        if depth > 0 {
            let first = tier1(element)
            let second = tier2(element)
            if first.hasPrefix("OK") || second.hasPrefix("OK") {
                return (
                    role: string(element, kAXRoleAttribute as String) ?? "?",
                    tier1: first, tier2: second, depth: depth
                )
            }
        }

        var children: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
            == .success, let kids = children as? [AXUIElement]
        {
            queue.append(contentsOf: kids.map { ($0, depth + 1) })
        }
    }
    return nil
}

/// Writes the selection back uppercased, then checks whether anything moved.
///
/// Section 7 item 2: `AXUIElementSetAttributeValue` returns `.success` for
/// writes that do nothing. Spike #30 measured that directly on Mail's
/// read-only HTML view. So the return code is reported, and then ignored in
/// favour of comparing the element's value before and after.
///
/// What #30 did *not* establish is whether the same holds for *editable* web
/// content -- a compose field rather than a received message. Tier 2 read is
/// proven; tier 2 write is not.
func attemptWrite(_ element: AXUIElement) -> [String] {
    var lines: [String] = []

    var selected: AnyObject?
    let readError = AXUIElementCopyAttributeValue(
        element, kAXSelectedTextAttribute as CFString, &selected)
    guard readError == .success, let original = selected as? String, !original.isEmpty else {
        return ["  write: skipped - nothing readable to write back (\(name(readError)))"]
    }

    let replacement = original.uppercased()
    if replacement == original {
        return ["  write: skipped - selection is already uppercase, pick mixed-case text"]
    }

    // The whole value, so a no-op is detectable even if the selection moves.
    let valueBefore = string(element, kAXValueAttribute as String)

    let writeError = AXUIElementSetAttributeValue(
        element, kAXSelectedTextAttribute as CFString, replacement as CFString)
    lines.append("  write: API returned \(name(writeError))")

    Thread.sleep(forTimeInterval: 0.6)
    let valueAfter = string(element, kAXValueAttribute as String)

    if let before = valueBefore, let after = valueAfter {
        if before == after {
            lines.append("  verify: value UNCHANGED -> SILENT NO-OP, whatever the API said")
        } else if after.contains(replacement) {
            lines.append("  verify: value changed and contains the replacement -> WRITE OK")
        } else {
            lines.append("  verify: value changed but does not contain the replacement -> SUSPECT")
        }
        return lines
    }

    // No AXValue to compare: fall back to re-reading the selection.
    var after: AnyObject?
    let backError = AXUIElementCopyAttributeValue(
        element, kAXSelectedTextAttribute as CFString, &after)
    guard backError == .success, let text = after as? String else {
        lines.append("  verify: could not read back (\(name(backError))) -> UNVERIFIED")
        return lines
    }
    lines.append(
        text == replacement
            ? "  verify: selection reads back as the replacement -> WRITE OK"
            : "  verify: selection still reads \"\(text.prefix(40))\" -> SILENT NO-OP")
    return lines
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
if writeMode {
    print("")
    print("*** WRITE MODE. This REPLACES the text you select with an uppercase")
    print("*** version of itself. Use a scratch document, not anything you care")
    print("*** about. Press Return to continue, or Ctrl-C to stop.")
    _ = readLine()
}
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

    print("  app:    \(app.label)")

    var (element, route) = focusedElement(pid: app.pid)
    if element == nil {
        // Arm Chromium's tree, then retry. Report the two separately: on
        // 2026-09-20 an element appeared in Outlook and Teams *after* an
        // arming that had returned attributeUnsupported, and the first version
        // of this message credited the arming for it. It had not done
        // anything -- the retry's extra wait had. Saying "appeared after
        // arming" there is the same class of mistake as a test that passes for
        // the wrong reason.
        let armed = enableManualAccessibility(pid: app.pid)
        print("  nothing yet; AXManualAccessibility -> \(armed); retrying in 3s")
        Thread.sleep(forTimeInterval: 3.0)
        (element, route) = focusedElement(pid: app.pid)
        if element != nil {
            let cause =
                armed == "success"
                ? "arming worked, or the extra wait did - cannot tell which"
                : "the extra wait, not the arming: that returned \(armed)"
            print("  -> an element appeared. Cause: \(cause)")
        }
    }

    guard let element else {
        print("  focused element: NONE (\(route))")
        print("  -> tier 3 only: nothing readable even after arming the tree")
        print("  ...switch back to the terminal for the next round")
        waitForReturnHome()
        continue
    }

    print("  route:  \(route)")
    print("  role:   \(string(element, kAXRoleAttribute as String) ?? "?")")
    let first = tier1(element)
    let second = tier2(element)
    print("  tier 1: \(first)")
    print("  tier 2: \(second)")

    if first.hasPrefix("OK") == false, second.hasPrefix("OK") == false {
        if let found = descendantWithSelection(element) {
            print("  descendant search: FOUND at depth \(found.depth), role \(found.role)")
            print("    tier 1: \(found.tier1)")
            print("    tier 2: \(found.tier2)")
            print("  -> the text is reachable; the focused element just is not it")
        } else {
            print("  descendant search: nothing selectable below the focused element")
            print("  -> tier 3, clipboard-only")
        }
    }

    if writeMode {
        for line in attemptWrite(element) { print(line) }
    }

    print("  ...switch back to the terminal for the next round")
    waitForReturnHome()
}

print("")
print("=== what the results mean ===")
print("  tier 1 OK                       -> native AppKit text, the easy case")
print("  tier 1 EMPTY/absent, tier 2 OK  -> WebKit, needs the text-marker path")
print("  both EMPTY or absent            -> clipboard-only (Electron), what #77 closes")
