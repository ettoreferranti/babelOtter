import Foundation
import Testing

@testable import BabelOtterKit

/// Records every operation in order, so "restore happened, and happened last"
/// is testable rather than assumed.
private final class FakePasteboard: PasteboardAccess, @unchecked Sendable {
    enum Operation: Equatable {
        case snapshot
        case restore
        case read
        case write(String)
        case await(timeout: Double)
    }

    private(set) var operations: [Operation] = []
    private(set) var writtenConcealed: [Bool] = []
    private(set) var contents: String?
    private(set) var changeCount = 1

    /// One entry per `awaitChange` call: whether the count moves.
    private var movements: [Bool]
    private let arriving: String?

    init(movements: [Bool], arriving: String?, initial: String? = "the user's own clipboard") {
        self.movements = movements
        self.arriving = arriving
        self.contents = initial
    }

    func snapshot() -> PasteboardSnapshot {
        operations.append(.snapshot)
        return PasteboardSnapshot(items: [["public.utf8-plain-text": Data((contents ?? "").utf8)]])
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        operations.append(.restore)
        contents = snapshot.items.first?["public.utf8-plain-text"]
            .flatMap { String(data: $0, encoding: .utf8) }
    }

    func readString() -> String? {
        operations.append(.read)
        return contents
    }

    func write(_ string: String, concealed: Bool) {
        operations.append(.write(string))
        writtenConcealed.append(concealed)
        contents = string
        changeCount += 1
    }

    func awaitChange(from previous: Int, timeout: Double) -> Bool {
        operations.append(.await(timeout: timeout))
        let moved = movements.isEmpty ? false : movements.removeFirst()
        if moved {
            changeCount += 1
            contents = arriving
        }
        return moved
    }
}

private final class FakeKeystrokes: KeystrokeSending, @unchecked Sendable {
    private(set) var copies = 0
    private(set) var pastes = 0
    func copy() { copies += 1 }
    func paste() { pastes += 1 }
}

@Suite("Clipboard capture restores on every path")
struct ClipboardCaptureTests {

    @Test("a successful capture returns the text and restores the clipboard")
    func successfulCapture() {
        let pasteboard = FakePasteboard(movements: [true], arriving: "selected words")
        let keystrokes = FakeKeystrokes()
        let result = ClipboardCapture(pasteboard: pasteboard, keystrokes: keystrokes).capture()

        #expect((try? result.get()) == "selected words")
        #expect(pasteboard.contents == "the user's own clipboard")
        #expect(pasteboard.operations.last == .restore)
        #expect(keystrokes.copies == 1)
    }

    /// The defect that pasted 36 characters of unrelated older clipboard
    /// content into a live Mail message while the probe was being written.
    @Test("an unmoved changeCount is failure, never the stale clipboard")
    func unmovedChangeCountIsFailure() {
        let pasteboard = FakePasteboard(
            movements: [false, false], arriving: nil, initial: "something copied an hour ago")
        let result = ClipboardCapture(
            pasteboard: pasteboard, keystrokes: FakeKeystrokes()).capture()

        #expect(result == .failure(.nothingCaptured))
        #expect(pasteboard.operations.contains(.read) == false,
            "reading at all is the bug: the stale contents would look like a capture")
    }

    @Test("exactly one retry is issued, with the longer window")
    func retriesOnce() {
        let pasteboard = FakePasteboard(movements: [false, true], arriving: "arrived late")
        let keystrokes = FakeKeystrokes()
        let policy = ClipboardPolicy(retryTimeout: 4.0)
        let result = ClipboardCapture(
            pasteboard: pasteboard, keystrokes: keystrokes, policy: policy, firstTimeout: 2.0
        ).capture()

        #expect((try? result.get()) == "arrived late")
        #expect(keystrokes.copies == 2)
        #expect(pasteboard.operations.contains(.await(timeout: 2.0)))
        #expect(pasteboard.operations.contains(.await(timeout: 4.0)))
    }

    @Test("never more than one retry, for any number of failures")
    func neverMoreThanOneRetry() {
        let pasteboard = FakePasteboard(
            movements: [false, false, false, false], arriving: "never reached")
        let keystrokes = FakeKeystrokes()
        _ = ClipboardCapture(pasteboard: pasteboard, keystrokes: keystrokes).capture()
        #expect(keystrokes.copies == 2, "two attempts total: the first and one retry")
    }

    @Test("the clipboard is restored after a failed capture too")
    func restoresAfterFailure() {
        let pasteboard = FakePasteboard(movements: [false, false], arriving: nil)
        _ = ClipboardCapture(pasteboard: pasteboard, keystrokes: FakeKeystrokes()).capture()
        #expect(pasteboard.contents == "the user's own clipboard")
        #expect(pasteboard.operations.last == .restore)
    }

    @Test("a changeCount that moves without text is reported, and still restores")
    func movedButNoText() {
        let pasteboard = FakePasteboard(movements: [true], arriving: nil)
        let result = ClipboardCapture(
            pasteboard: pasteboard, keystrokes: FakeKeystrokes()).capture()
        #expect(result == .failure(.noTextOnPasteboard))
        #expect(pasteboard.operations.last == .restore)
    }

    @Test("an empty string arriving is not a capture")
    func emptyArrivalIsNotACapture() {
        let pasteboard = FakePasteboard(movements: [true], arriving: "")
        let result = ClipboardCapture(
            pasteboard: pasteboard, keystrokes: FakeKeystrokes()).capture()
        #expect(result == .failure(.noTextOnPasteboard))
    }

    @Test("the clipboard is saved before Command-C, never after")
    func savesBeforeCopying() {
        let pasteboard = FakePasteboard(movements: [true], arriving: "x")
        _ = ClipboardCapture(pasteboard: pasteboard, keystrokes: FakeKeystrokes()).capture()
        #expect(pasteboard.operations.first == .snapshot)
    }
}

@Suite("Clipboard replacement")
struct ClipboardReplacementTests {

    @Test("a replacement writes concealed, pastes, and restores")
    func pastes() {
        let pasteboard = FakePasteboard(movements: [], arriving: nil)
        let keystrokes = FakeKeystrokes()
        let outcome = ClipboardReplacement(pasteboard: pasteboard, keystrokes: keystrokes)
            .replace(with: "die Uebersetzung", activateSource: { true })

        #expect(outcome == .pasted)
        #expect(keystrokes.pastes == 1)
        #expect(pasteboard.writtenConcealed == [true])
        #expect(pasteboard.operations.last == .restore)
        #expect(pasteboard.contents == "the user's own clipboard")
    }

    @Test("a source application that has gone is not attempted, and nothing is written")
    func sourceGone() {
        let pasteboard = FakePasteboard(movements: [], arriving: nil)
        let keystrokes = FakeKeystrokes()
        let outcome = ClipboardReplacement(pasteboard: pasteboard, keystrokes: keystrokes)
            .replace(with: "text", activateSource: { false })

        guard case .notAttempted = outcome else {
            Issue.record("expected notAttempted, got \(outcome)")
            return
        }
        #expect(keystrokes.pastes == 0)
        #expect(pasteboard.operations.isEmpty, "nothing may touch the pasteboard")
    }

    @Test("empty text is refused before anything is activated")
    func emptyTextRefused() {
        let pasteboard = FakePasteboard(movements: [], arriving: nil)
        var activated = false
        let outcome = ClipboardReplacement(pasteboard: pasteboard, keystrokes: FakeKeystrokes())
            .replace(with: "", activateSource: { activated = true; return true })
        guard case .notAttempted = outcome else {
            Issue.record("expected notAttempted")
            return
        }
        #expect(!activated)
    }

    /// Copy stays available after a paste, because a paste cannot be confirmed.
    @Test("every outcome retains the result and keeps Copy available")
    func everyOutcomeKeepsCopy() {
        let outcomes: [ReplacementOutcome] = [
            .pasted, .failed(reason: "x"), .notAttempted(reason: "y"),
        ]
        for outcome in outcomes {
            #expect(outcome.retainsResult)
            #expect(outcome.offersCopy)
        }
    }
}

@Suite("Clipboard retry policy")
struct ClipboardPolicyDecisionTests {

    private let policy = ClipboardPolicy()

    @Test("a moved changeCount is accepted at any attempt")
    func movedAccepts() {
        for attempt in 0...4 {
            #expect(policy.decide(changeCountMoved: true, attempt: attempt) == .accept)
        }
    }

    @Test("the first failure retries, every later one gives up")
    func retryOnlyOnce() {
        #expect(policy.decide(changeCountMoved: false, attempt: 0) == .retry)
        for attempt in 1...5 {
            #expect(policy.decide(changeCountMoved: false, attempt: attempt) == .giveUp)
        }
    }
}
