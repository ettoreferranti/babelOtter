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
        #expect(SetupStep.allCases == [.accessibility, .model, .hotkeys, .tryIt])
        #expect(SetupStep.allCases.map(\.title) == ["Accessibility", "Model", "Hotkeys", "Try it"])
        #expect(SetupStep.accessibility < SetupStep.model)
        #expect(!(SetupStep.tryIt < SetupStep.hotkeys))
        #expect(!(SetupStep.model < SetupStep.model))
        #expect(SetupFlow.sampleSentence == "Please register for the module by Friday.")
    }

    // MARK: - Built-in server (#126)

    private func builtIn(
        _ state: BuiltInServerState?, daemon: DaemonProbe? = .reachable(models: ["mistral-small3.2:24b"]),
        model: String = "mistral-small3.2:24b"
    ) -> SetupFacts {
        SetupFacts(
            accessibilityGranted: true, server: .builtIn, builtInServer: state, daemon: daemon,
            chosenModel: model, testSucceeded: true)
    }

    @Test("on the built-in server, Model waits for the server, then for the download")
    func builtInModel() {
        let starting = "Starting the built-in server\u{2026}"
        #expect(SetupFlow.blocker(for: .model, facts: builtIn(nil)) == starting)
        #expect(SetupFlow.blocker(for: .model, facts: builtIn(.stopped)) == starting)
        #expect(SetupFlow.blocker(for: .model, facts: builtIn(.starting)) == starting)
        #expect(SetupFlow.blocker(for: .model, facts: builtIn(.failed("x."))) == "The built-in server stopped: x.")
        #expect(SetupFlow.blocker(for: .model, facts: builtIn(.running, daemon: nil)) == starting)
        #expect(SetupFlow.blocker(for: .model, facts: builtIn(.running, daemon: .unreachable(detail: "x"))) == starting)
        #expect(SetupFlow.blocker(for: .model, facts: builtIn(.running, daemon: .reachable(models: [])))
            == "Download Mistral Small 3.2 to continue.")
        #expect(SetupFlow.blocker(for: .model, facts: builtIn(.running, daemon: .reachable(models: []), model: "q:4b"))
            == "Download q:4b to continue.")
        #expect(SetupFlow.blocker(for: .model, facts: builtIn(.running)) == nil)
    }

    @Test("the user's own Ollama is offered only when it already has the built-in model")
    func offersOwnOllama() {
        var facts = builtIn(.running)
        #expect(!SetupFlow.offersOwnOllama(facts))
        facts.ownOllama = .unreachable(detail: "x")
        #expect(!SetupFlow.offersOwnOllama(facts))
        facts.ownOllama = .reachable(models: ["mistral-small3.2:latest"])
        #expect(!SetupFlow.offersOwnOllama(facts))
        facts.ownOllama = .reachable(models: ["qwen3:4b", "mistral-small3.2:24b"])
        #expect(SetupFlow.offersOwnOllama(facts))
    }

    @Test("a fresh install starts on its own Ollama only when that has the model")
    func initialServer() {
        #expect(SetupFlow.initialServer(ownOllama: .unreachable(detail: "x")) == .builtIn)
        #expect(SetupFlow.initialServer(ownOllama: .reachable(models: ["qwen3:4b"])) == .builtIn)
        #expect(SetupFlow.initialServer(ownOllama: .reachable(models: ["mistral-small3.2:24b"])) == .own)
    }

    @Test("the built-in model is shown by its name")
    func displayName() {
        #expect(SetupFlow.displayName(of: "mistral-small3.2:24b") == "Mistral Small 3.2")
        #expect(SetupFlow.displayName(of: "q:4b") == "q:4b")
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
