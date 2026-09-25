import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Daemon status and readiness")
struct DaemonStatusTests {

    private let policy = DaemonStatusPolicy()

    @Test("a reachable daemon holding the configured model is ready")
    func ready() {
        let status = policy.status(
            probe: .reachable(models: ["mistral-small3.2:24b"]),
            configuredModel: "mistral-small3.2:24b")
        #expect(status == .ready)
    }

    @Test("an unreachable daemon names the endpoint it tried")
    func unreachable() {
        let status = policy.status(
            probe: .unreachable(detail: "connection refused"),
            configuredModel: "m")
        guard case .unreachable(let detail) = status else {
            Issue.record("expected unreachable, got \(status)")
            return
        }
        #expect(detail.contains("connection refused"))
    }

    @Test("a reachable daemon without the configured model reports which is missing")
    func modelMissing() {
        let status = policy.status(
            probe: .reachable(models: ["llama3.1:8b"]),
            configuredModel: "mistral-small3.2:24b")
        #expect(status == .modelMissing("mistral-small3.2:24b"))
    }

    @Test("a daemon with no models at all is missing the configured one")
    func noModelsInstalled() {
        let status = policy.status(probe: .reachable(models: []), configuredModel: "m")
        #expect(status == .modelMissing("m"))
    }

    @Test("model matching is exact: a tag is part of the identity")
    func tagsAreNotInterchangeable() {
        let status = policy.status(
            probe: .reachable(models: ["mistral-small3.2:latest"]),
            configuredModel: "mistral-small3.2:24b")
        #expect(status == .modelMissing("mistral-small3.2:24b"))
    }

    // FR-UI-03: ready, degraded, blocked.
    @Test("each status maps to the readiness the menu bar shows")
    func readinessLevels() {
        #expect(DaemonStatus.ready.readiness == .ready)
        #expect(DaemonStatus.modelMissing("m").readiness == .degraded)
        #expect(DaemonStatus.unreachable(detail: "x").readiness == .blocked)
    }

    @Test("every status maps to some readiness, exhaustively")
    func everyStatusHasReadiness() {
        let all: [DaemonStatus] = [.ready, .modelMissing("m"), .unreachable(detail: "d")]
        for status in all {
            #expect(Readiness.allCases.contains(status.readiness))
        }
    }

    @Test("only ready can generate; the others explain why not")
    func canGenerate() {
        #expect(DaemonStatus.ready.canGenerate)
        #expect(DaemonStatus.modelMissing("m").canGenerate == false)
        #expect(DaemonStatus.unreachable(detail: "d").canGenerate == false)
        #expect(!DaemonStatus.modelMissing("m").detail.isEmpty)
        #expect(!DaemonStatus.unreachable(detail: "d").detail.isEmpty)
    }

    /// #45: status recovers without a restart. There is no latching state, so
    /// recovery is simply the next probe -- which is a property worth pinning,
    /// because a cached "blocked" is exactly how an app ends up needing one.
    @Test("recovery needs no intermediate state: the next probe decides")
    func recoversWithoutRestart() {
        let blocked = policy.status(probe: .unreachable(detail: "x"), configuredModel: "m")
        #expect(blocked.readiness == .blocked)
        let recovered = policy.status(probe: .reachable(models: ["m"]), configuredModel: "m")
        #expect(recovered == .ready)
    }

    @Test("a missing-model status names the model in its message")
    func missingModelMessageNamesIt() {
        #expect(DaemonStatus.modelMissing("mistral-small3.2:24b").detail
            .contains("mistral-small3.2:24b"))
    }
}
