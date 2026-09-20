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

// Parsed by walking, not by scanning for the first number. `--flash 250` has
// a numeric argument of its own, and a scan would have read 250 as the round
// count and then waited for two hundred and fifty app switches.
var pasteMode = false
var concealMode = false
var flashMode = false
var flashMilliseconds = 250
var explicitRounds: Int?

var remaining = Array(CommandLine.arguments.dropFirst())[...]
while let argument = remaining.first {
    remaining = remaining.dropFirst()
    switch argument {
    case "--paste": pasteMode = true
    case "--conceal": concealMode = true
    case "--flash":
        flashMode = true
        if let next = remaining.first, let value = Int(next) {
            flashMilliseconds = value
            remaining = remaining.dropFirst()
        }
    default:
        if let value = Int(argument) { explicitRounds = value }
    }
}

// --flash and --conceal are standalone measurements; they do not need capture
// rounds, and requiring an app switch first only gets in the way. `1...0` is a
// fatal range error, so zero rounds is expressed by skipping the loop.
let rounds = explicitRounds ?? ((flashMode || concealMode) ? 0 : 4)

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

// MARK: - Short-lived clipboard exposure

/// Places a marker, restores after `milliseconds`, and stops so the other Mac
/// can be checked.
///
/// The question: is a clipboard item that exists only briefly still exposed to
/// Universal Clipboard? It decides whether restoring quickly is a real
/// mitigation or theatre, and PRIVACY.md is materially different either way.
///
/// An earlier version tried to answer this locally by watching the size of
/// useractivityd's advertise blob. That does not work, and the failure is
/// worth recording: the blob did not change for a 217-byte marker held for
/// eight seconds, while a 34-byte marker left in place did produce a 34-byte
/// blob -- timestamped to the moment the *other* Mac pasted. So the blob is
/// written when a peer pulls, not when the clipboard changes, and its size is
/// evidence of a completed transfer rather than of an offer. Only the second
/// Mac can answer this.
func runFlash(milliseconds: Int) {
    let marker = "babelotter-flash-\(Int(Date().timeIntervalSince1970))"
    let saved = savePasteboard()

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let item = NSPasteboardItem()
    item.setString(marker, forType: .string)
    item.setString("", forType: concealedType)
    item.setString("", forType: sensitiveType)
    pasteboard.writeObjects([item])

    print("  placed: \(marker)")
    print("  holding it for \(milliseconds)ms, then restoring your clipboard")
    Thread.sleep(forTimeInterval: Double(milliseconds) / 1000.0)
    restorePasteboard(saved)

    let restored = NSPasteboard.general.string(forType: .string)
    print("  restored: \(restored?.prefix(40) ?? "<empty>")")
    print("")
    print("  Now press Command-V on your OTHER Mac and report what appears:")
    print("")
    print("    the marker above        -> a brief exposure still transfers.")
    print("                               Restoring quickly is NOT a mitigation.")
    print("    your restored clipboard -> the transfer happens when the peer")
    print("                               pastes, so a short window is a real")
    print("                               mitigation and PRIVACY.md softens.")
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

for round in stride(from: 1, through: rounds, by: 1) {
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
    var moved = waitForPasteboardChange(from: before)

    // One retry, with a longer window, when the first Command-C produces
    // nothing. Three of seven captures across the first two runs came back
    // empty -- including TextEdit, which should be the easy case -- and the
    // two candidate causes need telling apart: nothing was selected, or the
    // pasteboard had not caught up inside two seconds. A retry that succeeds
    // means timing, and #32 needs to retry too. A retry that also fails means
    // there was no selection, which is #35's case and not an error at all.
    if !moved {
        print("  capture: nothing after 2s; retrying once with a longer window")
        Thread.sleep(forTimeInterval: 0.5)
        sendCommand(keyC)
        moved = waitForPasteboardChange(from: before, timeout: 4.0)
        print(
            moved
                ? "  capture: the RETRY worked -> timing, not an empty selection"
                : "  capture: retry also produced nothing -> most likely no selection")
    }

    let captured = NSPasteboard.general.string(forType: .string)

    if !moved {
        print("  capture: FAILED - changeCount never moved")
    } else if let text = captured, !text.isEmpty {
        print("  capture: OK - \(text.count) chars")
    } else {
        print("  capture: changeCount moved but no string arrived")
    }

    // `moved` is not optional decoration. `captured` reads the pasteboard
    // whether or not Command-C did anything, so without this guard a failed
    // capture falls through to whatever was on the clipboard already and pastes
    // THAT into the user's document. It did exactly that on 2026-09-20: a Mail
    // round where Command-C produced nothing still pasted 36 characters of
    // unrelated older clipboard content into the message.
    if pasteMode, moved, let text = captured, !text.isEmpty, text != text.uppercased() {
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
        print("  paste: Command-V sent, \(replacement.count) chars, marked concealed")
        print("         expect to see: \(replacement.prefix(48))")
        print("         if the document is unchanged, Command-V did not land")
    } else if pasteMode, !moved {
        print("  paste: SKIPPED - capture failed, so there is nothing of yours to put back")
        print("         pasting here would insert unrelated clipboard content")
    } else if pasteMode {
        print("  paste: skipped - nothing captured, or the selection is already uppercase")
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

if flashMode {
    print("")
    print("=== short-lived clipboard test ===")
    runFlash(milliseconds: flashMilliseconds)
}

print("")
print("=== what to look for ===")
print("  capture OK in Teams/Word/VS Code -> the conduit works where Accessibility cannot")
print("  restore OK every round           -> save/restore is safe to build on")
print("  paste replaced the text          -> replacement works without Accessibility")
