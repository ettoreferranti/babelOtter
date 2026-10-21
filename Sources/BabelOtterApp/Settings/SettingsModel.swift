import AppKit
import BabelOtterKit
import Foundation

/// A settings control, for the refusal shown under it.
enum SettingsField: Hashable {
    case languages
    case retention
    case timeout
    case clipboard
    case model(Action)
    case hotKey(Action)
    /// The list's own buttons: add, delete, restore.
    case audiences
    case audience(String, AudienceField)
}

/// An audience's fields, for refusals under each.
enum AudienceField: Hashable {
    case name, register, guidance, terms
}

/// The installed models, as the Models tab last read them.
enum InstalledModels: Equatable {
    case loading
    case unavailable(String)
    case loaded([String])
}

/// One model download in progress, or how the last one ended.
struct ModelDownload: Equatable {
    let model: String
    var status: String
    /// 0 to 1 once Ollama reports sizes.
    var fraction: Double?
    var failure: String?
    var running: Bool
}

/// The settings window's state (#61). Every edit goes through
/// `SettingsEditor`, then straight to config.json; the watcher applies the
/// file as it applies a hand edit, and `configurationChanged` brings the
/// window back in step.
@MainActor
final class SettingsModel: ObservableObject {

    @Published private(set) var editor: SettingsEditor
    /// While not empty the window is read-only: saving would overwrite a
    /// file that is half-way through a hand edit.
    @Published private(set) var fileProblems: [String]
    @Published private(set) var refusals: [SettingsField: String] = [:]
    @Published private(set) var installed: InstalledModels = .loading
    @Published private(set) var download: ModelDownload?
    /// The audience just added, whose name field takes focus.
    @Published var addedAudience: String?
    /// What Restore did, under the list.
    @Published private(set) var audienceNote: String?

    private let source: ConfigurationSource
    private let client: () -> OllamaClient
    private let modelsChanged: () -> Void
    /// Re-reads config.json into the app, as the watcher would.
    private let reloadConfiguration: () -> Void
    /// Only the latest list of installed models is shown.
    private var modelsGeneration = 0
    let layout: () -> KeyLayout
    let suspendHotKeys: () -> Void
    let resumeHotKeys: () -> Void

    init(
        source: ConfigurationSource, layout: @escaping () -> KeyLayout,
        client: @escaping () -> OllamaClient, suspendHotKeys: @escaping () -> Void,
        resumeHotKeys: @escaping () -> Void, modelsChanged: @escaping () -> Void,
        reloadConfiguration: @escaping () -> Void
    ) {
        self.reloadConfiguration = reloadConfiguration
        self.source = source
        self.layout = layout
        self.client = client
        self.suspendHotKeys = suspendHotKeys
        self.resumeHotKeys = resumeHotKeys
        self.modelsChanged = modelsChanged
        editor = SettingsEditor(configuration: source.configuration)
        fileProblems = Self.problems(of: source)
    }

    var configuration: Configuration { editor.configuration }
    var isReadOnly: Bool { !fileProblems.isEmpty }

    /// The file changed, by the window or by hand.
    func configurationChanged() {
        editor = SettingsEditor(configuration: source.configuration)
        fileProblems = Self.problems(of: source)
    }

    /// Checks `change`, then writes the file. A refusal or a failed write
    /// is shown under `field`, and the file keeps its value.
    func edit(_ field: SettingsField, _ change: (inout SettingsEditor) throws -> Void) {
        guard !isReadOnly else { return }
        guard let store = source.store else { return }
        // The file first: a hand edit saved in the last moment, before the
        // watcher has settled (or with no watcher at all), must not be
        // overwritten by what the window last saw -- least of all one that
        // is half-way and broken.
        let current = store.load()
        if !current.fileFound || !current.problems.isEmpty || current.configuration != source.configuration {
            reloadConfiguration()
            refusals[field] = "config.json changed on disk - the window now shows it. Try again."
            return
        }
        var next = editor
        do {
            try change(&next)
        } catch let refusal as SettingsRefusal {
            refusals[field] = refusal.message
            return
        } catch {
            refusals[field] = error.localizedDescription
            return
        }
        do {
            try store.save(next.configuration)
        } catch {
            refusals[field] = "Could not save config.json: \(error.localizedDescription)"
            return
        }
        refusals[field] = nil
        editor = next
        // Apply it now rather than when the watcher settles: until then the
        // app's configuration would differ from the file, and the next edit
        // would be refused as "changed on disk".
        reloadConfiguration()
    }

    /// Selects config.json, or opens its folder.
    func showFile() {
        guard let store = source.store else { return }
        if FileManager.default.fileExists(atPath: store.fileURL.path(percentEncoded: false)) {
            NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
        } else {
            NSWorkspace.shared.open(store.directory)
        }
    }

    // MARK: - Audiences

    /// The id is made from this name, so it is asked for first. True when
    /// the audience was added.
    func addAudience(named name: String) -> Bool {
        var added: String?
        edit(.audiences) { editor in
            added = try editor.addAudience(named: name)
        }
        audienceNote = nil
        guard let added else { return false }
        addedAudience = added
        return true
    }



    func restoreShippedAudiences() {
        var result: (restored: [String], skipped: [String]) = ([], [])
        edit(.audiences) { editor in
            result = editor.restoreShippedAudiences()
        }
        var parts: [String] = []
        if !result.restored.isEmpty { parts.append("Restored " + result.restored.joined(separator: ", ") + ".") }
        if !result.skipped.isEmpty {
            parts.append("Not restored, the name is in use: " + result.skipped.joined(separator: ", ") + ".")
        }
        audienceNote = parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// An audience's fields leave the screen (another selected, the tab
    /// switched, deleted): a refusal still under one of them moves under
    /// the list, naming the audience, or would never be seen.
    func noteRefusalsOnLeaving(_ name: String, of id: String) {
        var message: String?
        for field in [AudienceField.name, .register, .guidance, .terms] {
            if let refused = refusals[.audience(id, field)] {
                if message == nil { message = refused }
                refusals[.audience(id, field)] = nil
            }
        }
        guard let message else { return }
        // A deleted audience has nothing left to save.
        if configuration.profile(id: id) == nil { return }
        audienceNote = "\(name): \(message) Not saved."
    }

    /// True when Restore would add at least one audience.
    var canRestoreAudiences: Bool {
        var trial = editor
        return !trial.restoreShippedAudiences().restored.isEmpty
    }

    func refuse(_ field: SettingsField, _ message: String) {
        refusals[field] = message
    }

    // MARK: - Models

    func loadModels() {
        modelsGeneration += 1
        let generation = modelsGeneration
        installed = .loading
        let client = client()
        Task {
            let result: InstalledModels
            do {
                result = .loaded(try await client.installedModels().map(\.name))
            } catch {
                result = .unavailable(error.localizedDescription)
            }
            if generation == modelsGeneration { installed = result }
        }
    }

    /// The window is shown again: fresh models, and a finished download's
    /// note gone.
    func windowShown() {
        if let download {
            if !download.running { self.download = nil }
        }
        loadModels()
    }

    func choice(for action: Action) -> ModelChoice? {
        guard case .loaded(let names) = installed else { return nil }
        return ModelChoice(configured: configuration.model(for: action), installed: names)
    }

    /// One at a time; it keeps running when the window closes.
    func startDownload(_ model: String) {
        if let download {
            if download.running { return }
        }
        download = ModelDownload(model: model, status: "Starting\u{2026}", fraction: nil, failure: nil, running: true)
        let stream = client().pull(model: model)
        Task {
            do {
                var finished = false
                for try await progress in stream {
                    download?.status = progress.status
                    download?.fraction = Self.fraction(progress)
                    finished = progress.isComplete
                }
                download?.running = false
                // Ollama reports a failure as a line the stream skips; only
                // its "success" line means the model is there.
                if !finished { download?.failure = "Ollama stopped before the download finished." }
            } catch {
                download?.running = false
                download?.failure = error.localizedDescription
            }
            loadModels()
            modelsChanged()
        }
    }

    private static func fraction(_ progress: PullProgress) -> Double? {
        guard let total = progress.total else { return nil }
        guard let completed = progress.completed else { return nil }
        if total <= 0 { return nil }
        return min(Double(completed) / Double(total), 1)
    }

    /// The file's own problems; a folder that could not be prepared is one.
    private static func problems(of source: ConfigurationSource) -> [String] {
        if source.store == nil { return source.problems }
        return source.fileProblems
    }
}
