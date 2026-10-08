import AppKit
import BabelOtterKit
import Observation

/// One invocation, from capture to a decision about the result.
@MainActor
@Observable
final class PopupModel {

    enum Phase: Equatable {
        case capturing
        case choosingDirection([LanguageCode])
        case translating
        case finished
        case failed(String)
        /// Accessibility is not granted, so nothing was captured.
        case needsAccessibility
    }

    let action: Action
    private(set) var phase: Phase = .capturing
    private(set) var direction: Direction?
    private(set) var text = ""
    private(set) var warnings: [String] = []
    private(set) var message: String?
    /// Set only by Correct, once its stream finishes. Never mutated by
    /// Translate.
    private(set) var correction: CorrectionResult?
    /// The audience profile, which carries the register (du/Sie). Starts at
    /// the one last chosen, so a user who writes to one audience all day
    /// picks it once.
    private(set) var profileID: String
    /// Free text for this invocation only ("shorter", "use Sie"). Never
    /// saved: it can quote the user's own text.
    var instruction = ""

    let configuration: Configuration
    private let translator: Translator
    private let corrector: Corrector
    private let close: @MainActor () -> Void
    private let reopen: @MainActor (PopupModel) -> Void
    private(set) var snapshot: SelectionSnapshot?
    private var consumer: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    /// Set the instant `dismiss()` runs, so a capture or a stream event that
    /// arrives afterward can never start -- or continue -- a translation
    /// nobody can see. `stop()` alone is not enough: it only cancels tasks
    /// that have already started, and `dismiss()` is reachable from
    /// `.capturing`, before any exist.
    private var isDismissed = false
    /// True for the whole of `replace()`'s pasteboard work, from the moment
    /// it starts until `settle(_:)` runs on every path, source-quit included.
    /// `AppDelegate` refuses a hotkey press while this is true, the same way
    /// it refuses one during a capture -- `ClipboardReplacement` and
    /// `ClipboardCapture`/`SelectionCapturer`'s clipboard tier both
    /// save/write/restore `NSPasteboard.general`, and letting a second one
    /// start mid-flight would interleave the two on the same pasteboard.
    private(set) var isReplacing = false

    init(
        action: Action, environment: AppEnvironment, close: @escaping @MainActor () -> Void,
        reopen: @escaping @MainActor (PopupModel) -> Void
    ) {
        self.action = action
        self.configuration = environment.configuration
        self.translator = Translator(configuration: environment.configuration, chat: environment.client)
        self.corrector = Corrector(configuration: environment.configuration, chat: environment.client)
        self.close = close
        self.reopen = reopen
        self.profileID = Self.initialProfileID(in: environment.configuration)
    }

    // MARK: - Profile and instruction

    /// UserDefaults holds only the profile's id -- never text -- as a
    /// per-machine convenience. An id that no longer names a configured
    /// profile falls back to Colleagues.
    private static let lastProfileKey = "lastProfileID"

    private static func initialProfileID(in configuration: Configuration) -> String {
        let saved = UserDefaults.standard.string(forKey: lastProfileKey)
        if let saved, configuration.profile(id: saved) != nil { return saved }
        return configuration.profile(id: AudienceProfile.colleagues.id)?.id
            ?? configuration.profiles.first?.id ?? AudienceProfile.colleagues.id
    }

    var profiles: [AudienceProfile] { configuration.profiles }

    /// Switching audience re-runs the translation already on screen, since
    /// the whole point is to see it in the other register.
    func selectProfile(_ id: String) {
        guard !isDismissed, id != profileID, configuration.profile(id: id) != nil else { return }
        profileID = id
        UserDefaults.standard.set(id, forKey: Self.lastProfileKey)
        regenerate()
    }

    /// Runs the translation (or correction) again with the current audience
    /// and instruction. Only once there is something to redo: a direction for
    /// Translate, a snapshot for Correct.
    func regenerate() {
        guard !isDismissed, !isReplacing else { return }
        if action == .correct {
            guard snapshot != nil else { return }
            runCorrection()
        } else {
            guard let direction else { return }
            run(direction)
        }
    }

    var canRegenerate: Bool {
        guard !isReplacing else { return false }
        if action == .correct {
            guard snapshot != nil else { return false }
        } else {
            guard direction != nil else { return false }
        }
        switch phase {
        case .translating, .finished, .failed: return true
        case .capturing, .choosingDirection, .needsAccessibility: return false
        }
    }

    private var styleNote: String? {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        return trimmed
    }

    func begin(with outcome: CaptureOutcome) {
        guard !isDismissed else { return }
        switch outcome {
        case .refused(let refusal):
            phase = .failed(refusal.detail)
        case .captured(let snapshot):
            self.snapshot = snapshot
            if action == .correct {
                runCorrection()
            } else {
                switch translator.direction(for: snapshot.text) {
                case .success(let direction):
                    run(direction)
                case .failure(.directionUnknown(let candidates)):
                    phase = .choosingDirection(candidates)
                case .failure(.languageNotConfigured(let code)):
                    phase = .failed("This looks like \(code), which is not one of your languages.")
                case .failure(.emptyResponse):
                    phase = .failed("Nothing came back from the model.")
                }
            }
        }
    }

    func choose(target: LanguageCode) {
        guard !isDismissed else { return }
        guard let direction = translator.direction(into: target) else { return }
        run(direction)
    }

    func swap() {
        guard !isDismissed, action != .correct else { return }
        guard let direction else { return }
        run(direction.swapped)
    }

    func displayName(_ code: LanguageCode) -> String {
        configuration.language(for: code)?.displayName ?? code.description
    }

    /// Shown instead of a capture when Accessibility is not granted (#28).
    func requireAccessibility() {
        guard !isDismissed else { return }
        phase = .needsAccessibility
    }

    func openAccessibilitySettings() {
        AccessibilitySettings.open()
        dismiss()
    }

    /// Whether there is a result worth keeping. For Translate this is just
    /// "finished"; for Correct, a text with no errors has nothing to paste or
    /// copy over the original (Replace stays disabled per the design: "No
    /// errors found").
    var canReplace: Bool {
        guard phase == .finished else { return false }
        if action == .correct {
            return correction?.hasNoErrors == false
        }
        return true
    }

    func copy() {
        guard canReplace else { return }
        SystemPasteboard().write(text, concealed: false)
        dismiss()
    }

    /// Pastes the translation over the original selection, through the
    /// clipboard, then restores whatever the user had copied before.
    ///
    /// `close()` hides the panel -- the panel must not be key when Command-V
    /// is posted -- but this deliberately does **not** call `dismiss()` and
    /// so never sets `isDismissed`. A replacement that turns out not to have
    /// been attempted (the source application quit, or something failed
    /// before the keystroke) reopens the same, still-live model with a
    /// message instead of losing the result behind a closed, dismissed
    /// popup.
    func replace() {
        guard canReplace, let snapshot, !isReplacing else { return }
        isReplacing = true
        let result = GeneratedResult(
            text: UserText(text), action: action,
            capturedViaPasteboard: snapshot.usedPasteboard)
        let pid = snapshot.application.processIdentifier

        guard let source = NSRunningApplication(processIdentifier: pid), !source.isTerminated else {
            settle(ResultCustody.afterSourceQuit(result: result))
            return
        }
        close()  // the panel must not be key when Command-V is posted
        source.activate()
        let text = self.text
        Task {
            var frontmost = false
            for _ in 0..<50 {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
                    frontmost = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            let isFront = frontmost
            let outcome = await Task.detached {
                ClipboardReplacement(
                    pasteboard: SystemPasteboard(), keystrokes: SyntheticKeystrokes(),
                    // Tools/clipboard-probe.swift measured 0.8s between
                    // Command-V and the target reading the pasteboard; less
                    // than that risks restoring the user's old clipboard
                    // before the paste lands, so the wrong text is what gets
                    // pasted.
                    settle: { Thread.sleep(forTimeInterval: 0.8) }
                ).replace(with: text, activateSource: { isFront })
            }.value
            settle(ResultCustody.afterReplacement(outcome, result: result))
        }
    }

    /// Runs on every path out of `replace()`, source-quit included, so
    /// `isReplacing` never stays stuck true past the pasteboard work it
    /// guards.
    private func settle(_ custody: Custody) {
        isReplacing = false
        message = custody.message
        guard custody.keepsPopupOpen else { return }
        reopen(self)
    }

    func dismiss() {
        isDismissed = true
        stop()
        close()
    }

    /// Cancelling the consumer ends the `for await`, which terminates the
    /// translator's stream, which cancels the HTTP request.
    private func stop() {
        consumer?.cancel()
        watchdog?.cancel()
        consumer = nil
        watchdog = nil
    }

    private var profile: AudienceProfile {
        configuration.profile(id: profileID) ?? .colleagues
    }

    /// Holds one run's `consumer` and `watchdog` so each can cancel the
    /// other without going through `self`. See the comment in
    /// `consume(_:apply:fail:)`.
    @MainActor
    private final class RunTasks {
        var consumer: Task<Void, Never>?
        var watchdog: Task<Void, Never>?
        /// When this run last heard from the model. The watchdog measures
        /// silence from here, not time since the run began.
        var lastActivity = ContinuousClock.now
    }

    /// Starts consuming `stream`, with the timeout watchdog and the stale-
    /// consumer protections described in the comment below. `apply` runs on
    /// the main actor for each event; `fail` maps a thrown error to a message.
    private func consume<Event: Sendable>(
        _ stream: LazyStream<Event>,
        apply: @escaping @MainActor (PopupModel, Event) -> Void,
        fail: @escaping @MainActor (any Error) -> String
    ) {
        let timeout = configuration.timeoutSeconds

        // Both tasks inherit the main actor, so they touch `self` directly.
        //
        // `consumer` and `watchdog` are a pair, each existing only to cancel
        // the other -- through `pair`, a holder created fresh for this one
        // `run()`, rather than through `self.consumer` / `self.watchdog`. A
        // cancelled `AsyncThrowingStream` iterator returns nil rather than
        // throwing, so a stale consumer -- cancelled by `stop()` because a
        // later run of either action (Swap, Regenerate, a new audience)
        // already replaced both properties -- can still reach the code after
        // the loop. Reading `self.watchdog` there would hand it whichever
        // watchdog happens to be current by
        // then, i.e. the new run's; `pair` is this run's own, so a stale
        // consumer only ever cancels the watchdog it was started alongside.
        // (A plain local `var` captured directly by both closures hits
        // Swift's "mutated after capture by sendable closure" diagnostic,
        // since `consumer` must capture it before `watchdog` exists --
        // `pair` sidesteps that by never being reassigned itself, only its
        // properties.)
        let pair = RunTasks()
        let consumer = Task { [weak self] in
            do {
                for try await event in stream {
                    // Events already buffered ahead of a cancellation --
                    // including `.finished` -- must not be applied once this
                    // consumer is stale; they would overwrite the new run's
                    // text and phase with the old run's.
                    guard !Task.isCancelled else { return }
                    pair.lastActivity = .now
                    if let self { apply(self, event) }
                }
            } catch {
                // A cancelled request can surface as a URL error rather than
                // CancellationError; either way the reason was set by
                // whoever cancelled.
                guard !Task.isCancelled else { return }
                self?.phase = .failed(fail(error))
            }
            guard !Task.isCancelled else { return }
            pair.watchdog?.cancel()
        }
        // Idle, not total: the run fails only after `timeout` seconds with no
        // event at all. A slow model streaming a long reply (measured
        // 2026-09-30: five short paragraphs took 59.9 s on the default 24B
        // model) is alive and must not be cut off; a stalled one still is.
        // Every text piece arrives as a `.progress` event, so silence here
        // means the model really has stopped sending.
        let watchdog = Task { [weak self] in
            while true {
                let deadline = pair.lastActivity.advanced(by: .seconds(timeout))
                try? await Task.sleep(until: deadline, clock: .continuous)
                guard !Task.isCancelled else { return }
                if ContinuousClock.now >= pair.lastActivity.advanced(by: .seconds(timeout)) {
                    break
                }
            }
            guard let self, self.phase == .translating else { return }
            pair.consumer?.cancel()
            self.phase = .failed(
                ResultCustody.afterCancellation(.timedOut).message ?? "Timed out.")
        }
        pair.consumer = consumer
        pair.watchdog = watchdog
        self.consumer = consumer
        self.watchdog = watchdog
    }

    private func run(_ direction: Direction) {
        guard !isDismissed, let snapshot else { return }
        stop()
        self.direction = direction
        text = ""
        warnings = []
        message = nil
        phase = .translating

        consume(
            translator.translate(
                snapshot.text, direction: direction, profile: profile, styleNote: styleNote),
            apply: { $0.apply($1) },
            fail: Self.describe)
    }

    private func apply(_ event: TranslationEvent) {
        switch event {
        case .started(let direction):
            self.direction = direction
        case .progress:
            break
        case .preview(let partial):
            text = partial.value
        case .finished(let result):
            text = result.text.value
            warnings = result.warnings
            phase = .finished
        }
    }

    private func runCorrection() {
        guard !isDismissed, let snapshot else { return }
        stop()
        correction = nil
        text = ""
        warnings = []
        message = nil
        phase = .translating
        consume(
            corrector.correct(snapshot.text, profile: profile, styleNote: styleNote),
            apply: { model, event in model.applyCorrection(event) },
            fail: Self.describeCorrection)
    }

    private func applyCorrection(_ event: CorrectionEvent) {
        switch event {
        case .started, .progress:
            break
        case .preview(let partial):
            text = partial.value
        case .finished(let result):
            correction = result
            text = result.corrected.value
            warnings = result.warnings
            phase = .finished
        }
    }

    private static func describeCorrection(_ error: any Error) -> String {
        if let failure = error as? CorrectionFailure {
            switch failure {
            case .notGerman: return "Correct works on German text."
            case .unreadableReply:
                return "The model's reply couldn't be read as a correction. Try Regenerate."
            case .structureLost: return "The model lost the text's structure. Try Regenerate."
            case .emptyResponse: return "Nothing came back from the model."
            }
        }
        return describe(error)
    }

    /// Names an error for what it is, rather than always blaming Ollama:
    /// only a transport failure means the daemon could not be reached.
    private static func describe(_ error: any Error) -> String {
        if let failure = error as? TranslationError {
            switch failure {
            case .emptyResponse:
                return "Nothing came back from the model."
            case .languageNotConfigured(let code):
                return "This looks like \(code), which is not one of your languages."
            case .directionUnknown:
                // Not reachable from here: `run(_:)` always calls in with an
                // already-resolved direction, and `direction(for:)` /
                // `direction(into:)` are what raise this, before a
                // translation ever starts.
                return "Could not tell which language this is."
            }
        }
        if error is OllamaTransportError || error is URLError {
            return "Ollama could not be reached. Is it running?"
        }
        return "The request failed: \(error.localizedDescription)"
    }
}
