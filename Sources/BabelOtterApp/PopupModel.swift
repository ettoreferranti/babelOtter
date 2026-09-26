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
    }

    private(set) var phase: Phase = .capturing
    private(set) var direction: Direction?
    private(set) var text = ""
    private(set) var warnings: [String] = []
    private(set) var message: String?

    let configuration: Configuration
    private let translator: Translator
    private let close: @MainActor () -> Void
    private(set) var snapshot: SelectionSnapshot?
    private var consumer: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    /// Set the instant `dismiss()` runs, so a capture or a stream event that
    /// arrives afterward can never start -- or continue -- a translation
    /// nobody can see. `stop()` alone is not enough: it only cancels tasks
    /// that have already started, and `dismiss()` is reachable from
    /// `.capturing`, before any exist.
    private var isDismissed = false

    init(environment: AppEnvironment, close: @escaping @MainActor () -> Void) {
        self.configuration = environment.configuration
        self.translator = Translator(configuration: environment.configuration, chat: environment.client)
        self.close = close
    }

    func begin(with outcome: CaptureOutcome) {
        guard !isDismissed else { return }
        switch outcome {
        case .refused(let refusal):
            phase = .failed(refusal.detail)
        case .captured(let snapshot):
            self.snapshot = snapshot
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

    func choose(target: LanguageCode) {
        guard !isDismissed else { return }
        guard let direction = translator.direction(into: target) else { return }
        run(direction)
    }

    func swap() {
        guard !isDismissed else { return }
        guard let direction else { return }
        run(direction.swapped)
    }

    func displayName(_ code: LanguageCode) -> String {
        configuration.language(for: code)?.displayName ?? code.description
    }

    func copy() {
        guard phase == .finished else { return }
        SystemPasteboard().write(text, concealed: false)
        dismiss()
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
        configuration.profile(id: AudienceProfile.colleagues.id) ?? .colleagues
    }

    private func run(_ direction: Direction) {
        guard !isDismissed, let snapshot else { return }
        stop()
        self.direction = direction
        text = ""
        warnings = []
        message = nil
        phase = .translating

        let stream = translator.translate(snapshot.text, direction: direction, profile: profile)
        let timeout = configuration.timeoutSeconds

        // Both tasks inherit the main actor, so they touch `self` directly.
        let consumer = Task { [weak self] in
            do {
                for try await event in stream { self?.apply(event) }
            } catch {
                // A cancelled request can surface as a URL error rather than
                // CancellationError; either way the reason was set by
                // whoever cancelled.
                guard !Task.isCancelled else { return }
                self?.phase = .failed(Self.describe(error))
            }
            self?.watchdog?.cancel()
        }
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, let self, self.phase == .translating else { return }
            consumer.cancel()
            self.phase = .failed(
                ResultCustody.afterCancellation(.timedOut).message ?? "Timed out.")
        }
        self.consumer = consumer
    }

    private func apply(_ event: TranslationEvent) {
        switch event {
        case .started(let direction):
            self.direction = direction
        case .preview(let partial):
            text = partial.value
        case .finished(let result):
            text = result.text.value
            warnings = result.warnings
            phase = .finished
        }
    }

    private static func describe(_ error: any Error) -> String {
        if let failure = error as? TranslationError, failure == .emptyResponse {
            return "Nothing came back from the model."
        }
        return "Ollama could not be reached. Is it running?"
    }
}
