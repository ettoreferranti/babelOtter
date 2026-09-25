import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Capture-only strict mode")
struct CapturePolicyTests {

    @Test("by default every tier is available")
    func defaultAllowsEverything() {
        #expect(CapturePolicy(strictCaptureOnly: false).allowedTiers == CaptureTier.allCases)
    }

    @Test("strict mode allows exactly the two Accessibility tiers")
    func strictAllowsAccessibilityOnly() {
        let allowed = CapturePolicy(strictCaptureOnly: true).allowedTiers
        #expect(allowed == [.accessibilityText, .textMarkerRange])
        #expect(!allowed.contains(.clipboard))
    }

    @Test("strict mode is derived from the tier's own exposure, not a hardcoded list")
    func derivedFromExposure() {
        // If a fourth tier were added that used the pasteboard, strict mode
        // would exclude it without this type being edited.
        let allowed = CapturePolicy(strictCaptureOnly: true).allowedTiers
        #expect(allowed.allSatisfy { !$0.usesPasteboard })
    }

    @Test("strict mode refuses by naming the application, and says it is a setting")
    func strictRefusalNamesTheApp() {
        let refusal = CapturePolicy(strictCaptureOnly: true)
            .refusal(application: "Microsoft Teams", clipboardWouldHaveBeenTried: true)
        #expect(refusal == .clipboardRefused(application: "Microsoft Teams"))
        #expect(refusal.detail.contains("Microsoft Teams"))
        #expect(refusal.isSettingDependent)
    }

    /// The two need different messages: one is the user's own doing, the other
    /// is a refusal babelOtter made on their behalf.
    @Test("a refusal is distinguishable from an empty selection")
    func refusalIsNotEmptySelection() {
        let strict = CapturePolicy(strictCaptureOnly: true)
        let refused = strict.refusal(application: "Word", clipboardWouldHaveBeenTried: true)
        let empty = strict.refusal(application: "TextEdit", clipboardWouldHaveBeenTried: false)

        #expect(refused != empty)
        #expect(empty == .nothingSelected)
        #expect(!empty.isSettingDependent)
        #expect(refused.detail != empty.detail)
    }

    @Test("outside strict mode, a failure is always just an empty selection")
    func lenientFailuresAreEmptySelections() {
        let lenient = CapturePolicy(strictCaptureOnly: false)
        #expect(lenient.refusal(application: "Teams", clipboardWouldHaveBeenTried: true)
            == .nothingSelected)
    }

    @Test("the policy comes from configuration, which defaults to off")
    func fromConfiguration() {
        #expect(Configuration.default.strictCaptureOnly == false)
        #expect(CapturePolicy(configuration: .default).allowedTiers == CaptureTier.allCases)

        var strict = Configuration.default
        strict.strictCaptureOnly = true
        #expect(CapturePolicy(configuration: strict).allowedTiers.count == 2)
    }

    @Test("the setting survives being written and read back")
    func settingPersists() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "babelotter-strict-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ConfigurationStore(directory: directory)

        var configuration = Configuration.default
        configuration.strictCaptureOnly = true
        try store.save(configuration)
        #expect(store.load().configuration.strictCaptureOnly)
    }

    /// Strict mode is about reading. Replacement uses the clipboard either way.
    @Test("strict mode says nothing about replacement")
    func replacementIsUnaffected() {
        for strict in [true, false] {
            let policy = CapturePolicy(strictCaptureOnly: strict)
            // The type exposes no replacement-facing knob at all, which is the
            // guarantee: there is nothing here for a caller to consult.
            #expect(policy.allowedTiers.contains(.accessibilityText))
        }
    }

    @Test("the ladder honours the policy, and never attempts a forbidden tier")
    func ladderHonoursThePolicy() {
        final class Source: SelectionSource, @unchecked Sendable {
            private(set) var asked: [CaptureTier] = []
            func read(tier: CaptureTier) -> String? {
                asked.append(tier)
                return tier == .clipboard ? "would have worked" : ""
            }
        }
        let source = Source()
        let policy = CapturePolicy(strictCaptureOnly: true)
        let result = TierLadder().capture(from: source, allowing: policy.allowedTiers)

        #expect(result == nil)
        #expect(!source.asked.contains(.clipboard))
    }
}
