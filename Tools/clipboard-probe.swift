// Is the clipboard conduit actually viable?
//
// Spike #30 named the clipboard "tier 3" and reached it by elimination -- it
// never simulated a Command-C or a Command-V. Every tier-3 verdict in
// docs/architecture.md therefore means "Accessibility cannot do it", not "the
// clipboard can". This measures the second claim.
//
// Per round, against whichever app you switch to:
//   1. save the pasteboard
//   2. Command-C, wait for changeCount to move, read what arrived
//   3. restore the pasteboard and verify the restore
//   4. with --paste: put an uppercase version back, Command-V, restore again
//
// Deliberately outside Sources/: not a SwiftPM target, not scanned by the
// architecture guards, and it imports AppKit, which the core may not.

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

setvbuf(stdout, nil, _IONBF, 0)

let arguments = Array(CommandLine.arguments.dropFirst())
let pasteMode = arguments.contains("--paste")
let concealMode = arguments.contains("--conceal")
// max(1,) because `for round in 1...0` is a fatal range error, and "run zero
// rounds" is a request a diagnostic should decline rather than crash on.
let rounds = max(1, Int(arguments.first { Int($0) != nil } ?? "4") ?? 4)

let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
let sensitiveType = NSPasteboard.PasteboardType("com.apple.is-sensitive")

// MARK: - Frontmost app, via the window list

struct Frontmost {
    let pid: pid_t
    let label: String
}

/// Not NSWorkspace: its frontmostApplication needs a run loop this tool never
/// starts, and reports a frozen value. Measured in the AX probe's history.
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

let host = frontmost()

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
            print("  waiting for you to switch away... (frontmost: \(frontmost()?.label ?? "?"))")
            lastBeat = Date()
        }
        Thread.sleep(forTimeInterval: 0.3)
    }
    return nil
}

func waitForReturnHome(timeout: TimeInterval = 180) {
    let deadline = Date().addingTimeInterval(timeout)
    var lastBeat = Date.distantPast
    while Date() < deadline {
        if frontmost()?.pid == host?.pid { return }
        if Date().timeIntervalSince(lastBeat) > 4 {
            print("  waiting for you to come back... (frontmost: \(frontmost()?.label ?? "?"))")
            lastBeat = Date()
        }
        Thread.sleep(forTimeInterval: 0.3)
    }
}

// MARK: - Pasteboard save and restore

/// Every type of every item, so the restore is faithful rather than
/// string-shaped. A tool that clobbers the user's clipboard while measuring
/// whether it can avoid clobbering the user's clipboard is not a useful tool.
func savePasteboard() -> [[NSPasteboard.PasteboardType: Data]] {
    (NSPasteboard.general.pasteboardItems ?? []).map { item in
        var stored: [NSPasteboard.PasteboardType: Data] = [:]
        for type in item.types {
            if let data = item.data(forType: type) { stored[type] = data }
        }
        return stored
    }
}

func restorePasteboard(_ saved: [[NSPasteboard.PasteboardType: Data]]) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard !saved.isEmpty else { return }
    let items = saved.map { stored -> NSPasteboardItem in
        let item = NSPasteboardItem()
        for (type, data) in stored { item.setData(data, forType: type) }
        return item
    }
    pasteboard.writeObjects(items)
}

func waitForPasteboardChange(from previous: Int, timeout: TimeInterval = 2.0) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if NSPasteboard.general.changeCount != previous { return true }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return false
}

// MARK: - Synthetic keystrokes

let keyC: CGKeyCode = 8
let keyV: CGKeyCode = 9

func sendCommand(_ key: CGKeyCode) {
    let source = CGEventSource(stateID: .combinedSessionState)
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
    else { return }
    down.flags = .maskCommand
    up.flags = .maskCommand
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

// MARK: - The rounds

print("=== clipboard conduit probe ===")
print("AXIsProcessTrusted: \(AXIsProcessTrusted() ? "YES" : "NO")")
guard AXIsProcessTrusted() else {
    print("")
    print("Synthetic keystrokes need the Accessibility grant. Grant it to this")
    print("terminal, quit it with Cmd-Q, reopen and rerun.")
    exit(1)
}

if pasteMode {
    print("")
    print("*** PASTE MODE ***")
    print("This presses Command-V in the app you switch to, replacing your")
    print("selection. Use a scratch document, not anything you care about.")
    print("")
    if isatty(FileHandle.standardInput.fileDescriptor) == 1 {
        print("Press Return in THIS TERMINAL to start, or Ctrl-C to stop", terminator: " > ")
        _ = readLine()
    } else {
        print("(stdin is not a terminal, so starting without a confirmation)")
    }
}

print("")
print("Switch to an app, SELECT SOME TEXT, and wait. Then come back here.")
print("Worth covering: Teams, Word, VS Code, Safari - the ones Accessibility cannot reach.")

for round in 1...rounds {
    print("")
    print("--- round \(round)/\(rounds): switch to an app and select text ---")
    guard let app = waitForForeignApp() else {
        print("  nothing came forward; stopping.")
        break
    }
    print("  app: \(app.label)")

    let saved = savePasteboard()
    print("  saved \(saved.count) pasteboard item(s)")
    let before = NSPasteboard.general.changeCount

    sendCommand(keyC)
    let moved = waitForPasteboardChange(from: before)
    let captured = NSPasteboard.general.string(forType: .string)

    if !moved {
        print("  capture: changeCount did not move -> Command-C PRODUCED NOTHING")
    } else if let text = captured, !text.isEmpty {
        print("  capture: OK - \(text.count) chars")
    } else {
        print("  capture: changeCount moved but no string arrived")
    }

    if pasteMode, let text = captured, !text.isEmpty, text != text.uppercased() {
        let replacement = text.uppercased()
        NSPasteboard.general.clearContents()
        let item = NSPasteboardItem()
        item.setString(replacement, forType: .string)
        // The concealment markers PRIVACY.md describes as unverified.
        item.setString("", forType: concealedType)
        item.setString("", forType: sensitiveType)
        NSPasteboard.general.writeObjects([item])

        sendCommand(keyV)
        Thread.sleep(forTimeInterval: 0.8)
        print("  paste: Command-V sent with \(replacement.count) chars, marked concealed")
        print("         check by eye whether the text was replaced")
    } else if pasteMode {
        print("  paste: skipped - nothing captured, or already uppercase")
    }

    restorePasteboard(saved)
    let restored = NSPasteboard.general.string(forType: .string)
    let original = saved.first?[.string].flatMap { String(data: $0, encoding: .utf8) }
    if original == restored {
        print("  restore: OK - previous clipboard is back")
    } else {
        print("  restore: MISMATCH")
        print("    was:  \(original?.prefix(40) ?? "<none>")")
        print("    now:  \(restored?.prefix(40) ?? "<none>")")
    }

    print("  ...switch back to the terminal for the next round")
    waitForReturnHome()
}

if concealMode {
    print("")
    print("=== concealment test ===")
    let marker = "babelotter-conceal-test-\(Int(Date().timeIntervalSince1970))"
    NSPasteboard.general.clearContents()
    let item = NSPasteboardItem()
    item.setString(marker, forType: .string)
    item.setString("", forType: concealedType)
    item.setString("", forType: sensitiveType)
    NSPasteboard.general.writeObjects([item])
    print("Placed a CONCEALED item on the pasteboard:")
    print("  \(marker)")
    print("")
    print("Now go to your other Mac and press Command-V somewhere.")
    print("  - the marker appears  -> concealment does NOT stop Universal Clipboard")
    print("  - nothing appears     -> concealment suppresses the sync")
    print("")
    print("Your previous clipboard has NOT been restored, so the test item survives.")
}

print("")
print("=== what to look for ===")
print("  capture OK in Teams/Word/VS Code -> the conduit works where Accessibility cannot")
print("  restore OK every round           -> save/restore is safe to build on")
print("  paste replaced the text          -> replacement works without Accessibility")
