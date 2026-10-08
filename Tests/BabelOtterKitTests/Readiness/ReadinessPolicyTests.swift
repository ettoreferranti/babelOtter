import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Readiness")
struct ReadinessPolicyTests {

    @Test("readiness is ordered by severity, so the worst of several is the max")
    func orderedBySeverity() {
        #expect(Readiness.ready < Readiness.degraded)
        #expect(Readiness.degraded < Readiness.blocked)
        #expect([Readiness.degraded, .blocked, .ready].max() == .blocked)
    }

    @Test("every action has the name the menu shows")
    func actionDisplayNames() {
        #expect(Action.translate.displayName == "Translate")
        #expect(Action.correct.displayName == "Correct")
        #expect(Action.explain.displayName == "Explain")
        #expect(Action.repitch.displayName == "Re-pitch")
    }
}
