import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Generation timeout and cancellation")
struct GenerationTimeoutTests {

    private let policy = GenerationTimeout(timeoutSeconds: 60)

    @Test("under the timeout, generation continues")
    func underTimeout() {
        #expect(policy.decide(elapsed: 59.9, userDismissed: false) == .proceed)
    }

    /// Boundary. A mutant flipping `>=` to `>` has to fail here.
    @Test("exactly at the timeout, generation is cancelled")
    func exactlyAtTimeout() {
        #expect(policy.decide(elapsed: 60, userDismissed: false) == .cancel(.timedOut))
    }

    @Test("past the timeout, generation is cancelled")
    func pastTimeout() {
        #expect(policy.decide(elapsed: 60.1, userDismissed: false) == .cancel(.timedOut))
    }

    @Test("a user dismiss cancels immediately, whatever the clock says")
    func dismissWins() {
        #expect(policy.decide(elapsed: 0, userDismissed: true) == .cancel(.userRequested))
    }

    @Test("a dismiss past the timeout is still reported as the user's doing")
    func dismissWinsOverTimeout() {
        #expect(policy.decide(elapsed: 999, userDismissed: true) == .cancel(.userRequested))
    }

    @Test("zero elapsed proceeds")
    func zeroElapsed() {
        #expect(policy.decide(elapsed: 0, userDismissed: false) == .proceed)
    }

    /// NFR-PERF-3 and FR-UI-07 both require it, so it is a property of the
    /// outcome rather than something a call site has to remember.
    @Test("every cancellation discards the partial result, exhaustively")
    func everyCancellationDiscards() {
        for reason in CancellationReason.allCases {
            #expect(GenerationOutcome.cancel(reason).discardsPartialResult)
            #expect(GenerationOutcome.cancel(reason).writesHistory == false)
        }
    }

    @Test("proceeding discards nothing and is not a history write either")
    func proceedingKeepsTheResult() {
        #expect(GenerationOutcome.proceed.discardsPartialResult == false)
        #expect(GenerationOutcome.proceed.writesHistory == false)
    }

    @Test("a completed generation is the only thing that writes history")
    func completionWritesHistory() {
        #expect(GenerationOutcome.completed.writesHistory)
        #expect(GenerationOutcome.completed.discardsPartialResult == false)
    }

    @Test("the timeout comes from configuration, not from a constant")
    func timeoutIsConfigured() {
        var configuration = Configuration.default
        configuration.timeoutSeconds = 5
        let short = GenerationTimeout(configuration: configuration)
        #expect(short.decide(elapsed: 5, userDismissed: false) == .cancel(.timedOut))
        #expect(short.decide(elapsed: 4.9, userDismissed: false) == .proceed)
    }

    @Test("a non-positive timeout never cancels on the clock")
    func nonPositiveTimeoutIsNotAnInstantCancel() {
        // A hand-edited config file can carry 0. Cancelling every generation
        // the instant it starts is not a defensible reading of that.
        let zero = GenerationTimeout(timeoutSeconds: 0)
        #expect(zero.decide(elapsed: 1000, userDismissed: false) == .proceed)
        #expect(zero.decide(elapsed: 0, userDismissed: true) == .cancel(.userRequested))
    }

    @Test("each cancellation reason carries a message naming what to do next")
    func reasonsExplainThemselves() {
        // Case-insensitive: these are sentences shown to a person, and the
        // assertion is about what they say, not how they are capitalised.
        #expect(CancellationReason.timedOut.detail.lowercased().contains("timed out"))
        #expect(CancellationReason.userRequested.detail.lowercased().contains("cancelled"))
        for reason in CancellationReason.allCases {
            #expect(!reason.detail.isEmpty)
        }
    }
}
