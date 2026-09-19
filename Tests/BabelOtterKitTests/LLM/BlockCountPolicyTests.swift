import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Block-count mismatches retry exactly once")
struct BlockCountPolicyTests {

    private let policy = BlockCountPolicy()

    @Test("matching counts on the first attempt proceed")
    func matchingFirstAttempt() {
        #expect(policy.decide(expected: 3, received: 3, attempt: 0) == .accept)
    }

    @Test("matching counts on the retry proceed")
    func matchingOnRetry() {
        #expect(policy.decide(expected: 3, received: 3, attempt: 1) == .accept)
    }

    @Test("a mismatch on the first attempt retries in whole-text mode")
    func mismatchRetries() {
        #expect(policy.decide(expected: 3, received: 2, attempt: 0) == .retryWholeText)
    }

    @Test("a mismatch on the retry degrades rather than retrying again")
    func mismatchOnRetryDegrades() {
        guard case .degrade = policy.decide(expected: 3, received: 2, attempt: 1) else {
            Issue.record("expected a degrade")
            return
        }
    }

    /// NFR-REL-2's real requirement, proven by exhaustion rather than by
    /// inspecting the caller: across every attempt and every mismatching pair,
    /// a retry is issued only on the very first attempt.
    @Test("never more than one retry, for any attempt or any mismatch")
    func neverMoreThanOneRetry() {
        for attempt in 0...5 {
            for expected in 0...4 {
                for received in 0...4 where expected != received {
                    let decision = policy.decide(
                        expected: expected, received: received, attempt: attempt)
                    if attempt == 0 {
                        #expect(decision == .retryWholeText)
                    } else {
                        #expect(
                            decision != .retryWholeText,
                            "attempt \(attempt) asked for another retry")
                    }
                }
            }
        }
    }

    @Test("matching counts accept at every attempt")
    func matchingAlwaysAccepts() {
        for attempt in 0...5 {
            for count in 0...4 {
                #expect(policy.decide(expected: count, received: count, attempt: attempt) == .accept)
            }
        }
    }

    @Test("zero expected and zero received is a match")
    func zeroIsAMatch() {
        #expect(policy.decide(expected: 0, received: 0, attempt: 0) == .accept)
    }

    @Test("the degrade reason names both counts, so the user sees what happened")
    func reasonNamesBothCounts() {
        guard case .degrade(let reason) = policy.decide(expected: 7, received: 3, attempt: 1) else {
            Issue.record("expected a degrade")
            return
        }
        #expect(reason.contains("7"))
        #expect(reason.contains("3"))
    }
}
