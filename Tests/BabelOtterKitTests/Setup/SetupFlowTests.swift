import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Each setup step checks itself before the window moves on")
struct SetupFlowTests {

    private func facts(
        granted: Bool = true, daemon: DaemonProbe? = .reachable(models: ["m"]),
        model: String = "m", tested: Bool = true
    ) -> SetupFacts {
        SetupFacts(accessibilityGranted: granted, daemon: daemon, chosenModel: model, testSucceeded: tested)
    }

    @Test("all satisfied: no step blocks")
    func allClear() {
        for step in SetupStep.allCases {
            #expect(SetupFlow.blocker(for: step, facts: facts()) == nil, "\(step)")
        }
    }

    @Test("Accessibility blocks until granted")
    func accessibility() {
        #expect(SetupFlow.blocker(for: .accessibility, facts: facts(granted: false)) == "Grant Accessibility to continue.")
    }

    @Test("Ollama blocks while checking and when unreachable")
    func ollama() {
        #expect(SetupFlow.blocker(for: .ollama, facts: facts(daemon: nil)) == "Checking Ollama\u{2026}")
        #expect(SetupFlow.blocker(for: .ollama, facts: facts(daemon: .unreachable(detail: "x"))) == "Ollama isn't running.")
        #expect(SetupFlow.blocker(for: .ollama, facts: facts(daemon: .reachable(models: []))) == nil)
    }

    @Test("the model blocks until the chosen one is installed, by its exact name")
    func model() {
        #expect(SetupFlow.blocker(for: .model, facts: facts(daemon: .reachable(models: ["m:latest"]))) == "m is not installed.")
        #expect(SetupFlow.blocker(for: .model, facts: facts(model: "other")) == "other is not installed.")
        #expect(SetupFlow.blocker(for: .model, facts: facts(daemon: nil)) == "Checking Ollama\u{2026}")
        #expect(SetupFlow.blocker(for: .model, facts: facts(daemon: .unreachable(detail: "x"))) == "Ollama isn't running.")
    }

    @Test("hotkeys never block; the test blocks until a translation finished")
    func hotkeysAndTest() {
        #expect(SetupFlow.blocker(for: .hotkeys, facts: facts(granted: false, daemon: nil, tested: false)) == nil)
        #expect(SetupFlow.blocker(for: .tryIt, facts: facts(tested: false)) == "Translate the sentence to finish.")
    }

    @Test("steps run in order, with titles")
    func order() {
        #expect(SetupStep.allCases == [.accessibility, .ollama, .model, .hotkeys, .tryIt])
        #expect(SetupStep.allCases.map(\.title) == ["Accessibility", "Ollama", "Model", "Hotkeys", "Try it"])
        #expect(SetupStep.ollama < SetupStep.model)
        #expect(!(SetupStep.tryIt < SetupStep.hotkeys))
        #expect(!(SetupStep.ollama < SetupStep.ollama))
        #expect(SetupFlow.sampleSentence == "Please register for the module by Friday.")
    }
}

@Suite("The setup window opens by itself only on a fresh install")
struct SetupGateTests {

    @Test("undecided: a fresh install opens, an existing one does not", arguments: [(false, true), (true, false)])
    func undecided(existed: Bool, opens: Bool) {
        #expect(SetupGate.shouldOpen(configurationExisted: existed, setupCompleted: nil) == opens)
        #expect(SetupGate.initialCompleted(configurationExisted: existed) == !opens)
    }

    @Test("once decided, it opens until finished, whether config.json exists or not", arguments: [
        (false, false, true), (true, false, true), (false, true, false), (true, true, false),
    ])
    func decided(existed: Bool, completed: Bool, opens: Bool) {
        #expect(SetupGate.shouldOpen(configurationExisted: existed, setupCompleted: completed) == opens)
    }
}
