import Foundation
import Testing

@testable import BabelOtterKit

@Suite("A generated result is never silently lost")
struct ResultCustodyTests {

    private let result = GeneratedResult(
        text: UserText("die fertige Uebersetzung"),
        action: .translate,
        capturedViaPasteboard: true)

    /// Every replacement outcome there is. #34's claim is about *all* paths,
    /// so the test walks all of them rather than sampling.
    private var everyOutcome: [ReplacementOutcome] {
        [.pasted, .failed(reason: "the paste did not land"),
         .notAttempted(reason: "the application has closed")]
    }

    @Test("every replacement outcome keeps the result and offers Copy")
    func everyOutcomeKeepsTheResult() {
        for outcome in everyOutcome {
            let custody = ResultCustody.afterReplacement(outcome, result: result)
            #expect(custody.result == result, "\(outcome) discarded the result")
            #expect(custody.offersCopy, "\(outcome) withdrew Copy")
        }
    }

    @Test("anything other than a clean paste keeps the popup open to say so")
    func failuresKeepThePopupOpen() {
        #expect(!ResultCustody.afterReplacement(.pasted, result: result).keepsPopupOpen)
        #expect(ResultCustody.afterReplacement(
            .failed(reason: "x"), result: result).keepsPopupOpen)
        #expect(ResultCustody.afterReplacement(
            .notAttempted(reason: "y"), result: result).keepsPopupOpen)
    }

    @Test("a failure explains itself; a clean paste has nothing to add")
    func messages() {
        #expect(ResultCustody.afterReplacement(.pasted, result: result).message == nil)
        #expect(ResultCustody.afterReplacement(
            .failed(reason: "the paste did not land"), result: result).message
            == "the paste did not land")
    }

    @Test("the source application quitting mid-generation still shows the result")
    func sourceQuitKeepsTheResult() {
        let custody = ResultCustody.afterSourceQuit(result: result)
        #expect(custody.result == result)
        #expect(custody.offersCopy)
        #expect(custody.keepsPopupOpen)
        #expect(custody.message?.isEmpty == false)
    }

    /// The one case with nothing to keep, and it is reached by a different
    /// door so that no other caller has to handle a nil result.
    @Test("a cancelled generation keeps nothing, for every reason")
    func cancellationKeepsNothing() {
        for reason in CancellationReason.allCases {
            let custody = ResultCustody.afterCancellation(reason)
            #expect(custody.result == nil)
            #expect(!custody.offersCopy)
            #expect(!custody.keepsPopupOpen)
            #expect(custody.message == reason.detail)
        }
    }

    @Test("cancellation and failure are different things")
    func cancellationIsNotFailure() {
        let cancelled = ResultCustody.afterCancellation(.userRequested)
        let failed = ResultCustody.afterReplacement(.failed(reason: "x"), result: result)
        #expect(cancelled.result == nil)
        #expect(failed.result != nil)
    }
}

@Suite("An empty selection never reaches the model")
struct ActionPreconditionTests {

    private func snapshot(_ text: String) -> SelectionSnapshot {
        SelectionSnapshot(
            text: UserText(text),
            tier: .accessibilityText,
            application: SourceApplication(
                processIdentifier: 1, bundleIdentifier: "com.example", name: "Example"))
    }

    @Test("an empty selection is refused")
    func emptyRefused() {
        #expect(ActionPrecondition.refusal(for: snapshot("")) == .nothingSelected)
    }

    @Test("a whitespace-only selection is refused too", arguments: [
        "   ", "\n", "\t\t", " \n \t ", "\r\n",
    ])
    func whitespaceRefused(_ text: String) {
        #expect(ActionPrecondition.refusal(for: snapshot(text)) == .nothingSelected)
    }

    @Test("a real selection passes")
    func realSelectionPasses() {
        #expect(ActionPrecondition.refusal(for: snapshot("Guten Morgen")) == nil)
    }

    @Test("a refusal for an empty selection is not setting-dependent")
    func emptyIsNotASettingProblem() {
        let refusal = try? #require(ActionPrecondition.refusal(for: snapshot("")))
        #expect(refusal?.isSettingDependent == false)
    }

    /// #35: nothing is requested. Checking before generation rather than after
    /// is the point -- the user is never left waiting on a request that was
    /// not worth making.
    @Test("the model is never consulted for an empty selection")
    func modelIsNeverCalled() {
        final class RecordingModel: @unchecked Sendable {
            private(set) var calls = 0
            func generate() { calls += 1 }
        }
        let model = RecordingModel()

        for text in ["", "   ", "\n\t"] {
            if ActionPrecondition.refusal(for: snapshot(text)) == nil { model.generate() }
        }
        #expect(model.calls == 0)

        if ActionPrecondition.refusal(for: snapshot("real")) == nil { model.generate() }
        #expect(model.calls == 1)
    }
}
