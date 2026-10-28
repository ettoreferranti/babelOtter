import AppKit
import BabelOtterKit
import Observation

/// The scratchpad window's state (#84): a text typed or pasted here, one
/// action run over it chunk by chunk on Run, and the result beside it.
///
/// Nothing is sent except by Run (or Continue). No capture, so no
/// Accessibility; the built-in server gate still applies. The text lives
/// only here, in memory, until lingoSwen quits.
@MainActor
@Observable
final class ScratchpadModel {

    /// A question that must be answered before anything is sent.
    enum Question: Equatable {
        case source([LanguageCode])
        case target(source: LanguageCode?, candidates: [LanguageCode])
    }

    var action: Action = .translate {
        didSet {
            if action != oldValue { answeredLanguage = nil; question = nil; refusal = nil }
        }
    }
    var source = "" {
        didSet {
            // A Swap was for the text it was made on.
            if source != oldValue { answeredLanguage = nil; question = nil; swapped = nil; refusal = nil }
        }
    }
    /// Translate: the target picked, nil for automatic.
    var target: LanguageCode? {
        didSet { swapped = nil }
    }
    /// Translate: set by Swap; wins over detection until another target is
    /// picked.
    private(set) var swapped: Direction?
    /// The audience picked; nil is automatic for Translate and the default
    /// audience for the other actions.
    var profileID: String?
    var styleNote = ""

    private(set) var status: ScratchpadStatus = .idle
    private(set) var question: Question?
    /// Why the last Run sent nothing ("already in English"). Kept apart
    /// from `status`, so the result on screen keeps its state.
    private(set) var refusal: String?
    /// The answer to "Which language is this?", until the text changes.
    private(set) var answeredLanguage: LanguageCode?
    /// The settings of the result on screen.
    private(set) var ran: ScratchpadSettings?

    /// The result so far: finished chunks and the one being written.
    private(set) var resultText = ""
    private(set) var correction: CorrectionResult?
    private(set) var explanation: ExplanationResult?
    private(set) var warnings: [String] = []
    /// Translate's direction and audience, as the last run reported them.
    private(set) var direction: Direction?
    private(set) var reportedAudience: AudienceProfile?
    private(set) var audienceInferred = false
    private(set) var copied = false

    /// Set by `AppDelegate` on every server change; nil for the user's own
    /// Ollama (#126).
    var serverState: BuiltInServerState?

    private let environment: @MainActor () -> AppEnvironment
    private let record: @MainActor (HistoryRecord) -> Void
    private let openSetup: @MainActor () -> Void

    /// The run in progress or interrupted, so Continue can pick it up.
    private var plan: ChunkPlan?
    private var task: ChunkTask?
    /// The configuration the run started with: Continue and the History
    /// record use it, so one text never mixes two models.
    private var runEnvironment: AppEnvironment?
    private var completed: [ChunkOutput] = []
    private var preview = ""
    private var tasks: RunTasks?

    init(
        environment: @escaping @MainActor () -> AppEnvironment,
        record: @escaping @MainActor (HistoryRecord) -> Void,
        openSetup: @escaping @MainActor () -> Void
    ) {
        self.environment = environment
        self.record = record
        self.openSetup = openSetup
    }

    // MARK: - What the window shows

    var configuration: Configuration { environment().configuration }

    var settings: ScratchpadSettings {
        ScratchpadSettings(
            action: action, source: source, target: target, swapped: swapped, profileID: profileID,
            styleNote: styleNote, language: answeredLanguage)
    }

    var policy: ScratchpadPolicy {
        ScratchpadPolicy(status: status, current: settings, ran: ran, serverProblem: serverProblem)
    }

    /// Mirrors the hotkeys' gate: no text to the built-in port until our own
    /// server answers there.
    private var serverProblem: String? {
        guard let serverState else { return nil }
        if case .running = serverState { return nil }
        return serverState.status
    }

    var showsSetupButton: Bool { serverProblem != nil }

    var profiles: [AudienceProfile] { configuration.profiles }

    var defaultProfile: AudienceProfile {
        profiles.first { $0.id == AudienceProfile.colleagues.id } ?? profiles.first ?? .colleagues
    }

    /// The picker's label for "nothing picked".
    var automaticLabel: String {
        if action == .translate { return "Audience: from the text" }
        return "Audience: " + defaultProfile.name
    }

    /// Three or more languages: the Into menu, as the popup's (#81).
    var usesTargetMenu: Bool { TargetChoice.usesMenu(configuration: configuration) }

    var enabledLanguages: [LanguageCode] { configuration.enabledLanguages.map(\.code) }

    func displayName(_ code: LanguageCode) -> String {
        configuration.language(for: code)?.displayName ?? code.description
    }

    /// "German → English" once a translation ran, or the swapped direction.
    var directionTitle: String? {
        guard let shown = swapped ?? direction else { return nil }
        return displayName(shown.source) + " \u{2192} " + displayName(shown.target)
    }

    var audienceNote: String? {
        guard action == .translate, let reportedAudience, profileID == nil else { return nil }
        if audienceInferred { return "\u{2726} " + reportedAudience.name + ", guessed from the text" }
        return reportedAudience.name
    }

    // MARK: - Commands

    func swap() {
        guard let shown = swapped ?? direction else { return }
        let reversed = shown.swapped
        target = reversed.target
        swapped = reversed
    }

    func showSetup() { openSetup() }

    func run() {
        guard policy.canRun else { return }
        if policy.continues, let plan, let task, let runEnvironment {
            start(plan, task, settings: settings, environment: runEnvironment, continuing: true)
            return
        }
        resolveAndStart()
    }

    func stop() {
        guard policy.isRunning else { return }
        // Every chunk is in: the joined result is already on its way.
        if let plan, completed.count >= plan.chunks.count { return }
        cancelTasks()
        status = .interrupted(done: completed.count, of: plan?.chunks.count ?? 0, reason: nil)
    }

    func answer(source code: LanguageCode) {
        guard policy.canRun else { return }
        answeredLanguage = code
        question = nil
        resolveAndStart()
    }

    func answer(target code: LanguageCode) {
        guard case .target(let source, _) = question else { return }
        guard policy.canRun else { return }
        question = nil
        // Kept as the Into choice only where the window shows that menu.
        if usesTargetMenu { target = code }
        let translator = Translator(configuration: configuration, chat: environment().client)
        guard let direction = translator.direction(from: source, into: code) else { return }
        begin(.translate(direction, audienceRequest), settings: settings)
    }

    func copy() {
        guard policy.canCopy else { return }
        SystemPasteboard().write(resultText, concealed: false)
        copied = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.copied = false
        }
    }

    // MARK: - Settling the task

    private var styleNoteValue: String? {
        let trimmed = styleNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return trimmed
    }

    private var chosenProfile: AudienceProfile? {
        guard let profileID else { return nil }
        return profiles.first { $0.id == profileID }
    }

    private var audienceRequest: AudienceRequest {
        if let chosenProfile { return .fixed(chosenProfile) }
        return .infer(profiles: profiles, fallback: defaultProfile)
    }

    /// Settles the language once, on the whole text, as the popup does:
    /// run, refuse, or ask.
    private func resolveAndStart() {
        question = nil
        refusal = nil
        let environment = environment()
        let text = UserText(source)
        let configuration = environment.configuration
        switch action {
        case .translate:
            resolveDirection(text, Translator(configuration: configuration, chat: environment.client))
        case .repitch:
            if let answeredLanguage {
                return begin(.repitch(answeredLanguage, chosenProfile ?? defaultProfile), settings: settings)
            }
            let translator = Translator(configuration: configuration, chat: environment.client)
            switch translator.language(for: text) {
            case .success(let code):
                begin(.repitch(code, chosenProfile ?? defaultProfile), settings: settings)
            case .failure(.directionUnknown(_, let candidates)):
                question = .source(candidates)
            case .failure(let error):
                refuse(PopupModel.describe(error))
            }
        case .correct, .explain:
            resolveTextLanguage(text, configuration, environment.client)
        }
    }

    private func resolveDirection(_ text: UserText, _ translator: Translator) {
        if let swapped { return begin(.translate(swapped, audienceRequest), settings: settings) }
        let result: Result<Direction, TranslationError>
        if let answeredLanguage {
            if let target, let direction = translator.direction(from: answeredLanguage, into: target) {
                return begin(.translate(direction, audienceRequest), settings: settings)
            }
            result = translator.direction(from: answeredLanguage, remembered: remembered)
        } else {
            result = translator.direction(for: text, remembered: remembered)
        }
        switch result {
        case .success(let direction):
            begin(.translate(direction, audienceRequest), settings: settings)
        case .failure(.directionUnknown(let detected, let candidates)):
            let known = detected ?? answeredLanguage
            if known == nil, usesTargetMenu {
                question = .source(enabledLanguages)
            } else {
                question = .target(source: known, candidates: candidates)
            }
        case .failure(let error):
            refuse(PopupModel.describe(error))
        }
    }

    /// A picked target is used for every source but itself.
    private var remembered: [LanguageCode: LanguageCode] {
        guard let target else { return [:] }
        var map: [LanguageCode: LanguageCode] = [:]
        for code in enabledLanguages where code != target { map[code] = target }
        return map
    }

    private func resolveTextLanguage(_ text: UserText, _ configuration: Configuration, _ client: OllamaClient) {
        let make: (LanguageCode) -> ChunkTask = { [self] code in
            if action == .explain { return .explain(code) }
            return .correct(code, chosenProfile ?? defaultProfile)
        }
        if let answeredLanguage { return begin(make(answeredLanguage), settings: settings) }
        let resolution: TextLanguageResolution
        if action == .explain {
            resolution = Explainer(configuration: configuration, chat: client).language(for: text)
        } else {
            resolution = Corrector(configuration: configuration, chat: client).language(for: text)
        }
        switch resolution {
        case .known(let code):
            begin(make(code), settings: settings)
        case .mine(let code):
            refuse("This is already in \(displayName(code)).")
        case .notEnabled(let code):
            refuse("This looks like \(code), which is not one of your languages.")
        case .ask(let candidates):
            question = .source(candidates)
        }
    }

    /// Nothing was sent: the reason goes in the bar, the old result stays.
    private func refuse(_ reason: String) {
        refusal = reason
    }

    // MARK: - Running

    private func begin(_ task: ChunkTask, settings: ScratchpadSettings) {
        let plan: ChunkPlan
        if case .explain = task {
            plan = .whole(source)
        } else {
            plan = ChunkPlan(source)
        }
        start(plan, task, settings: settings, environment: environment(), continuing: false)
    }

    private func start(
        _ plan: ChunkPlan, _ task: ChunkTask, settings: ScratchpadSettings, environment: AppEnvironment,
        continuing: Bool
    ) {
        cancelTasks()
        refusal = nil
        if !continuing {
            completed = []
            correction = nil
            explanation = nil
            warnings = []
            reportedAudience = nil
            audienceInferred = false
            if case .translate(let direction, _) = task { self.direction = direction }
        }
        self.plan = plan
        self.task = task
        runEnvironment = environment
        ran = settings
        preview = ""
        resultText = plan.join(completed.map(\.text))
        status = .running(chunk: completed.count, of: plan.chunks.count)

        let runner = ChunkedRun(configuration: environment.configuration, chat: environment.client)
        consume(
            runner.run(plan, task: task, styleNote: styleNoteValue, completed: completed),
            timeout: environment.configuration.timeoutSeconds)
    }

    private func apply(_ event: ChunkedEvent) {
        switch event {
        case .chunkStarted(let index, let count):
            preview = ""
            status = .running(chunk: index, of: count)
        case .progress:
            break
        case .audience(let profile, let inferred):
            reportedAudience = profile
            audienceInferred = inferred
        case .preview(let partial):
            preview = partial
            showPartial()
        case .chunkFinished(_, let output):
            completed.append(output)
            preview = ""
            showPartial()
        case .finished(let result):
            finish(result)
        }
    }

    private func showPartial() {
        guard let plan else { return }
        var texts = completed.map(\.text)
        if !preview.isEmpty { texts.append(preview) }
        resultText = plan.join(texts)
    }

    private func finish(_ result: ChunkedResult) {
        resultText = result.text
        warnings = result.warnings
        correction = result.correction
        explanation = result.explanation
        if let translation = result.translation {
            reportedAudience = translation.audience
            audienceInferred = translation.audienceInferred
        }
        status = .finished
        let configuration = (runEnvironment ?? environment()).configuration
        let made = result.record(
            model: configuration.model(for: result.task.action), myLanguage: configuration.myLanguageCode,
            date: Date())
        if let made { record(made) }
    }

    private func fail(_ error: any Error) {
        let reason: String
        switch task {
        case .correct: reason = PopupModel.describeCorrection(error)
        case .explain: reason = PopupModel.describeExplanation(error, configuration)
        case .translate, .repitch, nil: reason = PopupModel.describe(error)
        }
        // The popup's wording names its own button.
        let button = completed.isEmpty ? "Run" : "Continue"
        interrupt(reason.replacingOccurrences(of: "Try Regenerate.", with: "Press \(button) to try again."))
    }

    private func interrupt(_ reason: String) {
        preview = ""
        showPartial()
        status = .interrupted(done: completed.count, of: plan?.chunks.count ?? 0, reason: reason)
    }

    private func timedOut() {
        cancelTasks()
        interrupt(ResultCustody.afterCancellation(.timedOut).message ?? "Timed out.")
    }

    // MARK: - Consuming, with the popup's idle watchdog

    @MainActor
    private final class RunTasks {
        var consumer: Task<Void, Never>?
        var watchdog: Task<Void, Never>?
        var lastActivity = ContinuousClock.now
    }

    private func cancelTasks() {
        tasks?.consumer?.cancel()
        tasks?.watchdog?.cancel()
        tasks = nil
    }

    /// As `PopupModel.consume`: idle, not total. Each chunk keeps the stream
    /// busy while the model writes, so a long text never times out as a
    /// whole; a model that goes silent for `timeout` seconds does. The pair
    /// is this run's own, so a stale consumer never touches a newer run.
    private func consume(_ stream: LazyStream<ChunkedEvent>, timeout: Double) {
        let pair = RunTasks()
        pair.consumer = Task { [weak self] in
            do {
                for try await event in stream {
                    guard !Task.isCancelled else { return }
                    pair.lastActivity = .now
                    self?.apply(event)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.fail(error)
            }
            pair.watchdog?.cancel()
        }
        pair.watchdog = Task { [weak self] in
            while true {
                try? await Task.sleep(until: pair.lastActivity.advanced(by: .seconds(timeout)), clock: .continuous)
                guard !Task.isCancelled else { return }
                if ContinuousClock.now >= pair.lastActivity.advanced(by: .seconds(timeout)) { break }
            }
            guard let self, self.tasks === pair else { return }
            self.timedOut()
        }
        tasks = pair
    }
}
