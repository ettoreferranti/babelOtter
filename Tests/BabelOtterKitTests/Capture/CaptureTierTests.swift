import Foundation
import Testing

@testable import BabelOtterKit

/// Answers whatever it was told to, and records what it was asked.
private final class FakeSource: SelectionSource, @unchecked Sendable {
    private let answers: [CaptureTier: String?]
    private(set) var asked: [CaptureTier] = []

    init(_ answers: [CaptureTier: String?]) {
        self.answers = answers
    }

    func read(tier: CaptureTier) -> String? {
        asked.append(tier)
        return answers[tier] ?? nil
    }
}

@Suite("The capture ladder accepts a tier only if it produces text")
struct CaptureTierTests {

    private let ladder = TierLadder()

    @Test("tier 1 returning text wins, and no later tier is consulted")
    func tierOneWins() {
        let source = FakeSource([.accessibilityText: "hello"])
        let result = ladder.capture(from: source)
        #expect(result?.tier == .accessibilityText)
        #expect(result?.text == "hello")
        #expect(source.asked == [.accessibilityText])
    }

    @Test("tier 1 absent falls through to tier 2")
    func fallsToTierTwo() {
        let source = FakeSource([.accessibilityText: nil, .textMarkerRange: "from webkit"])
        let result = ladder.capture(from: source)
        #expect(result?.tier == .textMarkerRange)
        #expect(source.asked == [.accessibilityText, .textMarkerRange])
    }

    /// The VS Code case, and the single most misleading result spike #30
    /// produced. Every attribute is advertised; every one returns empty. A
    /// ladder that accepted a non-nil answer would stop at tier 1 and capture
    /// nothing.
    @Test("tiers returning an EMPTY string are not success: the VS Code case")
    func emptyStringIsNotSuccess() {
        let source = FakeSource([
            .accessibilityText: "", .textMarkerRange: "", .clipboard: "from the clipboard",
        ])
        let result = ladder.capture(from: source)
        #expect(result?.tier == .clipboard)
        #expect(source.asked == [.accessibilityText, .textMarkerRange, .clipboard])
    }

    @Test("whitespace-only is empty too, so it falls through")
    func whitespaceIsNotSuccess() {
        let source = FakeSource([.accessibilityText: "   \n\t ", .clipboard: "real text"])
        #expect(ladder.capture(from: source)?.tier == .clipboard)
    }

    @Test("all tiers empty yields nothing rather than an empty capture")
    func allEmpty() {
        let source = FakeSource([.accessibilityText: "", .textMarkerRange: nil, .clipboard: ""])
        #expect(ladder.capture(from: source) == nil)
        #expect(source.asked == CaptureTier.allCases)
    }

    @Test("a restricted tier list is honoured, and nothing outside it is asked")
    func restrictedTiers() {
        let source = FakeSource([.accessibilityText: "", .clipboard: "would have worked"])
        let result = ladder.capture(
            from: source, allowing: [.accessibilityText, .textMarkerRange])
        #expect(result == nil)
        #expect(!source.asked.contains(.clipboard), "a forbidden tier must not be attempted")
    }

    @Test("the default order is tier 1, then 2, then the clipboard")
    func defaultOrder() {
        #expect(CaptureTier.allCases == [.accessibilityText, .textMarkerRange, .clipboard])
    }

    @Test("only the clipboard tier exposes text to the pasteboard")
    func pasteboardExposure() {
        #expect(CaptureTier.clipboard.usesPasteboard)
        #expect(!CaptureTier.accessibilityText.usesPasteboard)
        #expect(!CaptureTier.textMarkerRange.usesPasteboard)
    }
}

@Suite("A selection snapshot carries what the action needs, and no more")
struct SelectionSnapshotTests {

    private func snapshot(_ text: String, tier: CaptureTier = .accessibilityText)
        -> SelectionSnapshot
    {
        SelectionSnapshot(
            text: UserText(text),
            tier: tier,
            application: SourceApplication(
                processIdentifier: 42, bundleIdentifier: "com.example.app", name: "Example"))
    }

    @Test("empty and whitespace-only selections report as empty")
    func emptiness() {
        #expect(snapshot("").isEmpty)
        #expect(snapshot("   \n ").isEmpty)
        #expect(!snapshot("something").isEmpty)
    }

    @Test("a clipboard capture discloses that it used the pasteboard")
    func disclosesPasteboardUse() {
        #expect(snapshot("x", tier: .clipboard).usedPasteboard)
        #expect(!snapshot("x", tier: .textMarkerRange).usedPasteboard)
    }

    /// NFR-P3. A snapshot is the most log-attractive value in the app.
    @Test("the captured text does not appear in a description or a dump")
    func textIsNotLoggable() {
        let secret = "kennwort-im-klartext"
        let subject = snapshot(secret)

        #expect(!String(describing: subject.text).contains(secret))
        var dumped = ""
        dump(subject, to: &dumped)
        #expect(!dumped.contains(secret), "dump() reads stored properties directly")
    }

    @Test("the source application is recorded for later re-activation")
    func recordsTheApplication() {
        let subject = snapshot("x")
        #expect(subject.application.processIdentifier == 42)
        #expect(subject.application.bundleIdentifier == "com.example.app")
    }
}
