import BabelOtterKit
import Foundation

// The evaluation harness (spec 2026-09-30). Every decision lives in the kit;
// this file reads the golden set, calls the real pipelines, times them,
// prints and saves. It never runs in CI: CI has no Ollama.
//
// It prints golden-set text and model output. That is allowed here and
// nowhere else, because the golden set is synthetic (NFR-P8).

let usage = """
    usage: swift run babelotter-eval [--models a,b] [--only correct|translate|<case-id>,...]
                                     [--repeat N] [--compare evals/results/<file>.json]
    """

/// Generous, because it is an idle timeout: the transport fails a request
/// only after this long with no data at all.
let idleTimeoutSeconds: TimeInterval = 180

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func contents(_ path: String) -> Data {
    guard let data = FileManager.default.contents(atPath: path) else {
        fail("Could not read \(path). Run babelotter-eval from the repository root.")
    }
    return data
}

func seconds(since start: ContinuousClock.Instant) -> Double {
    let parts = (ContinuousClock.now - start).components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
}

func git(_ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/git")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

struct Attempt<Outcome: Sendable>: Sendable {
    let outcome: Outcome
    let output: String?
    let detail: String?
    let seconds: Double
}

func correct(_ testCase: CorrectionCase, model: String, client: OllamaClient) async -> Attempt<CorrectionOutcome> {
    var configuration = Configuration.default
    configuration.models[.correct] = model
    configuration.doNotTranslate = testCase.terms
    let corrector = Corrector(configuration: configuration, chat: client)
    let profile = configuration.profile(id: testCase.profileID) ?? .colleagues
    let start = ContinuousClock.now
    do {
        for try await event in corrector.correct(UserText(testCase.text), profile: profile) {
            if case .finished(let result) = event {
                return Attempt(
                    outcome: .corrected(result), output: result.corrected.value, detail: nil,
                    seconds: seconds(since: start))
            }
        }
        return Attempt(
            outcome: .failed(.other), output: nil, detail: "the stream ended without a result",
            seconds: seconds(since: start))
    } catch {
        return Attempt(
            outcome: .failed(EvalFailure(error)), output: nil, detail: String(describing: error),
            seconds: seconds(since: start))
    }
}

func translate(_ testCase: TranslationCase, model: String, client: OllamaClient) async -> Attempt<TranslationOutcome> {
    var configuration = Configuration.default
    configuration.models[.translate] = model
    configuration.doNotTranslate = testCase.terms
    let translator = Translator(configuration: configuration, chat: client)
    let profile = configuration.profile(id: testCase.profileID) ?? .colleagues
    let start = ContinuousClock.now
    do {
        for try await event in translator.translate(
            UserText(testCase.text), direction: testCase.direction.direction, profile: profile)
        {
            if case .finished(let result) = event {
                return Attempt(
                    outcome: .translated(result.text.value), output: result.text.value, detail: nil,
                    seconds: seconds(since: start))
            }
        }
        return Attempt(
            outcome: .failed(.other), output: nil, detail: "the stream ended without a result",
            seconds: seconds(since: start))
    } catch {
        return Attempt(
            outcome: .failed(EvalFailure(error)), output: nil, detail: String(describing: error),
            seconds: seconds(since: start))
    }
}

func progress(_ model: String, _ caseID: String, _ seconds: Double, passed: Bool) -> String {
    let id = caseID.padding(toLength: max(caseID.count, 28), withPad: " ", startingAt: 0)
    let verdict = passed ? "pass" : "miss"
    return "\(model)  \(id)  \(String(format: "%6.1f", seconds))s  \(verdict)"
}

// MARK: - Setup

let arguments: EvalArguments
do {
    arguments = try EvalArguments.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    fail("\(error)\n\n\(usage)")
}

let golden: GoldenSet
do {
    golden = try GoldenSet.load(
        correction: contents("evals/golden/correction.json"),
        translation: contents("evals/golden/translation.json"))
} catch {
    fail("The golden set is invalid: \(error)")
}

let selected: (correction: [CorrectionCase], translation: [TranslationCase])
do {
    selected = try arguments.cases(from: golden)
} catch {
    fail("\(error)")
}

var baseline: EvalRun?
if let path = arguments.compare {
    do {
        baseline = try EvalRun.decode(contents(path))
    } catch {
        fail("Could not read \(path) as an earlier run: \(error)")
    }
}

let client = OllamaClient.loopback(timeout: idleTimeoutSeconds)
let installed: [String]
do {
    installed = try await client.installedModels().map(\.name)
} catch {
    fail("Ollama could not be reached on 127.0.0.1:11434. Start it with `ollama serve` and try again.")
}

var notes: [String] = []
let models: [String]
if let requested = arguments.models {
    models = requested.filter { installed.contains($0) }
    notes += requested.filter { !installed.contains($0) }.map { "\($0): not installed, skipped" }
} else {
    models = installed
}
if models.isEmpty {
    fail("No model to run. Installed: \(installed.isEmpty ? "none" : installed.joined(separator: ", "))")
}

let commit = (git(["rev-parse", "--short", "HEAD"]) ?? "unknown")
    + ((git(["status", "--porcelain"]) ?? "").isEmpty ? "" : "-dirty")
let startedAt = Date()

// MARK: - Run

var records: [CaseRecord] = []
var correctionSummaries: [CorrectionSummary] = []
var translationSummaries: [TranslationSummary] = []
var misses: [String] = []

for model in models {
    if !selected.correction.isEmpty {
        var scores: [CorrectionScore] = []
        var times: [Double] = []
        var missesByRun: [[String]] = []
        for run in 1...arguments.repeatCount {
            var runMisses: [String] = []
            for testCase in selected.correction {
                let attempt = await correct(testCase, model: model, client: client)
                let score = CorrectionScorer.score(testCase, outcome: attempt.outcome)
                let missed = EvalReport.correctionMisses(model: model, testCase: testCase, score: score)
                print(progress(model, testCase.id, attempt.seconds, passed: missed.isEmpty))
                runMisses += missed
                scores.append(score)
                times.append(attempt.seconds)
                records.append(CaseRecord(
                    model: model, caseID: testCase.id, run: run, seconds: attempt.seconds,
                    output: attempt.output, failureDetail: attempt.detail, correction: score,
                    translation: nil))
            }
            missesByRun.append(runMisses)
        }
        misses += EvalReport.collapsedMisses(missesByRun)
        correctionSummaries.append(CorrectionSummary(model: model, scores: scores, seconds: times, runs: arguments.repeatCount))
    }
    if !selected.translation.isEmpty {
        var scores: [TranslationScore] = []
        var times: [Double] = []
        var missesByRun: [[String]] = []
        for run in 1...arguments.repeatCount {
            var runMisses: [String] = []
            for testCase in selected.translation {
                let attempt = await translate(testCase, model: model, client: client)
                let score = TranslationScorer.score(testCase, outcome: attempt.outcome)
                let missed = EvalReport.translationMisses(model: model, testCase: testCase, score: score)
                print(progress(model, testCase.id, attempt.seconds, passed: missed.isEmpty))
                runMisses += missed
                scores.append(score)
                times.append(attempt.seconds)
                records.append(CaseRecord(
                    model: model, caseID: testCase.id, run: run, seconds: attempt.seconds,
                    output: attempt.output, failureDetail: attempt.detail, correction: nil,
                    translation: score))
            }
            missesByRun.append(runMisses)
        }
        misses += EvalReport.collapsedMisses(missesByRun)
        translationSummaries.append(TranslationSummary(model: model, scores: scores, seconds: times, runs: arguments.repeatCount))
    }
}

// MARK: - Report

// The baseline is rebuilt over this run's cases only, so an --only run or a
// golden set that has changed since is still compared like with like.
let comparable = baseline?.comparable(to: records)
if let path = arguments.compare, let baseline, let comparable {
    let when = DateFormatter()
    when.locale = Locale(identifier: "en_US_POSIX")
    when.dateFormat = "yyyy-MM-dd HH:mm"
    notes.append("Compared with \(path) (commit \(baseline.commit), \(when.string(from: baseline.startedAt)))")
    for model in models {
        guard let absent = comparable.missing[model] else { continue }
        notes.append(
            "\(model): not in the baseline, so not compared: \(absent.joined(separator: ", "))"
                + " (they still count in this run's column)")
    }
}

print("")
for note in notes { print(note) }
if !correctionSummaries.isEmpty {
    print(EvalReport.table("Correction", correctionSummaries, baseline: comparable?.correction ?? []))
    print("")
}
if !translationSummaries.isEmpty {
    print(EvalReport.table("Translation", translationSummaries, baseline: comparable?.translation ?? []))
    print("")
}
if !misses.isEmpty {
    print("Misses")
    for line in misses { print("  " + line) }
    print("")
}

let run = EvalRun(
    startedAt: startedAt, commit: commit, repeatCount: arguments.repeatCount, correction: correctionSummaries,
    translation: translationSummaries, records: records)
let directory = "evals/results"
do {
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let path = directory + "/" + EvalRun.fileName(startedAt: startedAt, commit: commit)
    try run.encoded().write(to: URL(filePath: path))
    print("Saved \(path)")
} catch {
    fail("Could not save the results: \(error)")
}
