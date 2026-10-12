import Testing

@testable import BabelOtterKit

@Suite("The hotkeys to register, keeping what works")
struct HotKeyPlanTests {

    private let launch = HotKeyPlan.launchCombinations
    private let us = KeyLayoutTests.us
    private let swiss = KeyLayoutTests.swissGerman

    private func plan(
        _ translate: HotKeyBinding = .useDefault, _ correct: HotKeyBinding = .useDefault,
        previous: [Action: HotKeyCombination]? = nil, layout: KeyLayout? = nil
    ) -> HotKeyPlan {
        HotKeyPlan.make(
            bindings: HotKeyBindings(translate: translate, correct: correct),
            previous: previous ?? launch, layout: layout ?? us)
    }

    @Test("the launch combinations are the ones registered before #26")
    func launchCombinations() {
        #expect(launch[.translate] == HotKeyCombination(
            keyCode: 0x11, modifiers: 0x1800, displayName: "Control-Option-T"))
        #expect(launch[.correct] == HotKeyCombination(
            keyCode: 0x08, modifiers: 0x1800, displayName: "Control-Option-C"))
        #expect(HotKeyPlan.actions == [.translate, .correct])
    }

    @Test("no hotkeys field gives both defaults and no issues")
    func noField() {
        let result = HotKeyPlan.make(bindings: nil, previous: [:], layout: us)
        #expect(result.combinations == launch)
        #expect(result.issues.isEmpty)
    }

    @Test("off leaves that action without a hotkey, and is no issue")
    func off() {
        let result = plan(.useDefault, .off)
        #expect(result.combinations[.correct] == nil)
        #expect(result.combinations[.translate] != nil)
        #expect(result.issues.isEmpty)
    }

    @Test("a typo keeps the previous hotkey and names the problem")
    func typoKeepsPrevious() {
        let result = plan(.text("contrl+option+T"))
        #expect(result.combinations[.translate] == launch[.translate])
        #expect(result.issues == [HotKeyIssue(
            action: .translate, text: "contrl+option+T", problem: .unknownPart("contrl"))])
        #expect(result.issues[0].description
            == "translate hotkey \"contrl+option+T\": unknown key or modifier \"contrl\"")
    }

    @Test("a typo with nothing previous leaves no hotkey")
    func typoWithoutPrevious() {
        let result = plan(.text("contrl+option+T"), previous: [:])
        #expect(result.combinations[.translate] == nil)
        #expect(result.issues.count == 1)
    }

    @Test("a character missing from the layout keeps the previous hotkey")
    func notOnLayoutKeepsPrevious() {
        let result = plan(.text("control+option+\u{FC}"))
        #expect(result.combinations[.translate] == launch[.translate])
        #expect(result.issues[0].problem == .notOnLayout("\u{FC}"))
    }

    @Test("both on one combination: Translate gets it, Correct keeps its previous one")
    func duplicate() {
        let result = plan(.text("control+option+T"), .text("control+option+T"))
        #expect(result.combinations[.translate] == launch[.translate])
        #expect(result.combinations[.correct] == launch[.correct])
        #expect(result.issues == [HotKeyIssue(
            action: .correct, text: "control+option+T", problem: .sharedWith(.translate))])
        #expect(result.issues[0].description
            == "correct hotkey \"control+option+T\": is also the Translate hotkey")
    }

    @Test("a duplicate whose previous combination Translate has taken leaves Correct with none")
    func duplicateOfPrevious() {
        let result = plan(.text("control+option+C"), .text("control+option+C"))
        #expect(result.combinations[.translate]?.keyCode == 0x08)
        #expect(result.combinations[.correct] == nil)
        #expect(result.issues.last?.problem == .previousTakenBy(.translate))
    }

    @Test("a Correct typo keeps its previous combination only if Translate has not taken it")
    func typoKeepsPreviousOnlyIfFree() {
        let result = plan(.text("control+option+C"), .text("contrl+option+X"))
        #expect(result.combinations[.translate]?.keyCode == 0x08)
        #expect(result.combinations[.correct] == nil)
        #expect(result.issues == [
            HotKeyIssue(action: .correct, text: "contrl+option+X", problem: .unknownPart("contrl")),
            HotKeyIssue(action: .correct, text: "contrl+option+X", problem: .previousTakenBy(.translate)),
        ])
    }

    @Test("losing the previous hotkey is said in so many words")
    func previousTakenDetail() {
        #expect(HotKeyProblem.previousTakenBy(.translate).detail
            == "so this action has no hotkey: its previous one is now the Translate hotkey")
    }

    @Test("swapping the two combinations in one save is no duplicate")
    func swapIsNoDuplicate() {
        let result = plan(.text("control+option+C"), .text("control+option+T"))
        #expect(result.combinations[.translate]?.keyCode == 0x08)
        #expect(result.combinations[.correct]?.keyCode == 0x11)
        #expect(result.issues.isEmpty)
    }

    @Test("a layout change moves a character key to where the layout types it")
    func layoutChange() {
        let onUS = plan(.text("control+option+Z"))
        let onSwiss = plan(.text("control+option+Z"), previous: onUS.combinations, layout: swiss)
        #expect(onUS.combinations[.translate]?.keyCode == 0x06)
        #expect(onSwiss.combinations[.translate]?.keyCode == 0x10)
    }
}
