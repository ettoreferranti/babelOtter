import Testing

@testable import BabelOtterKit

private let golden = GoldenSet(
    correction: [
        CorrectionCase(id: "c1", text: "a", profileID: "colleagues", terms: [], fixes: [], mustNot: [], clean: true),
        CorrectionCase(id: "c2", text: "b", profileID: "colleagues", terms: [], fixes: [], mustNot: [], clean: true),
    ],
    translation: [
        TranslationCase(id: "t1", text: "c", direction: .englishToSwissGerman, profileID: "colleagues", terms: [], reference: "d"),
    ])

@Suite("Eval: arguments and case selection")
struct EvalArgumentsTests {

    @Test("no arguments means every model, every case, one run")
    func defaults() throws {
        let parsed = try EvalArguments.parse([])
        #expect(parsed == EvalArguments(models: nil, selection: .everything, repeatCount: 1, compare: nil))
    }

    @Test("every option is read")
    func everyOption() throws {
        let parsed = try EvalArguments.parse([
            "--models", "a:1, b:2", "--only", "c1,t1", "--repeat", "3", "--compare", "evals/results/x.json",
        ])
        #expect(parsed.models == ["a:1", "b:2"])
        #expect(parsed.selection == .cases(["c1", "t1"]))
        #expect(parsed.repeatCount == 3)
        #expect(parsed.compare == "evals/results/x.json")
    }

    @Test("--repeat 1 is accepted")
    func repeatOnce() throws {
        #expect(try EvalArguments.parse(["--repeat", "1"]).repeatCount == 1)
    }

    @Test("--only takes an action name")
    func onlyAction() throws {
        #expect(try EvalArguments.parse(["--only", "correct"]).selection == .correctionOnly)
        #expect(try EvalArguments.parse(["--only", "translate"]).selection == .translationOnly)
    }

    @Test("bad arguments are refused with a reason", arguments: [
        ["--model", "a"],
        ["--models"],
        ["--models", "--only", "correct"],
        ["--models", " , "],
        ["--repeat", "0"],
        ["--repeat", "two"],
        ["--only", "correct", "--only", "translate"],
        ["stray"],
    ])
    func refused(arguments: [String]) {
        #expect(throws: EvalArgumentError.self) { try EvalArguments.parse(arguments) }
    }

    @Test("selection picks the cases it names")
    func selection() throws {
        let all = try EvalArguments(models: nil, selection: .everything, repeatCount: 1, compare: nil).cases(from: golden)
        #expect(all.correction.map(\.id) == ["c1", "c2"])
        #expect(all.translation.map(\.id) == ["t1"])
        let correctOnly = try EvalArguments(models: nil, selection: .correctionOnly, repeatCount: 1, compare: nil).cases(from: golden)
        #expect(correctOnly.translation.isEmpty)
        #expect(correctOnly.correction.count == 2)
        let translateOnly = try EvalArguments(models: nil, selection: .translationOnly, repeatCount: 1, compare: nil).cases(from: golden)
        #expect(translateOnly.correction.isEmpty)
        #expect(translateOnly.translation.count == 1)
        let named = try EvalArguments(models: nil, selection: .cases(["c2", "t1"]), repeatCount: 1, compare: nil).cases(from: golden)
        #expect(named.correction.map(\.id) == ["c2"])
        #expect(named.translation.map(\.id) == ["t1"])
    }

    @Test("a mistyped case id is an error naming it, never an empty run")
    func unknownCase() {
        let arguments = EvalArguments(models: nil, selection: .cases(["c1", "c9"]), repeatCount: 1, compare: nil)
        #expect(throws: EvalArgumentError(message: "no case named c9")) { try arguments.cases(from: golden) }
    }
}
