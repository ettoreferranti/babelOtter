import BabelOtterKit
import Foundation

/// Where the configuration comes from, and what is wrong with it.
///
/// Reads `~/Library/Application Support/ch.lingoswen/config.json`, writing
/// the defaults there on first launch so the file can be edited by hand
/// until settings exist (M3). Every failure falls back so the app still
/// starts; `problems` is what makes a fallback visible (NFR-P7, FR-CFG-03).
@MainActor
final class ConfigurationSource {

    private(set) var configuration: Configuration
    /// Each worded to follow "config.json: " in the menu. Empty when nothing
    /// is wrong.
    private(set) var problems: [String]
    /// Nil when the folder could not be prepared: nothing to reload then.
    let store: ConfigurationStore?
    /// True while the configuration is the defaults only because config.json
    /// could not be read, so history pauses (#69). A first launch's defaults
    /// are real; a reload with problems keeps whatever was in use (#26).
    private(set) var isFallback: Bool
    /// What is wrong with config.json itself as last read, each worded to
    /// follow "config.json: "; empty when it reads cleanly. While not empty
    /// the settings window is read-only, so it never overwrites the file
    /// (#61).
    private(set) var fileProblems: [String] = []
    /// Whether config.json was there at launch: its absence marks a fresh
    /// install, for the setup window (#70). True when the folder could not
    /// be prepared, so a broken folder does not pass for a first run.
    let fileExistedAtLaunch: Bool

    init() {
        let locator = AppStorage.locator()
        do {
            let store = try ConfigurationStore.inApplicationSupport(locator: locator)
            let loaded = store.load()
            let result = ConfigurationReload.apply(
                previous: .default, loaded: loaded, fileExists: loaded.fileFound, isLaunch: true)
            var problems = Self.summaries(result.problems)
            var configuration = result.configuration
            if loaded.fileFound, !result.problems.isEmpty {
                // A file that is there but unreadable belongs to someone
                // already using lingoSwen: the defaults' built-in server would
                // offer them a 15 GB download (#126).
                configuration.modelServer = nil
            }
            if !loaded.fileFound {
                do {
                    try store.save(result.configuration)
                } catch {
                    problems += ["using defaults - could not write the file (\(error.localizedDescription))"]
                }
            } else if result.problems.isEmpty, let added = configuration.addingMissingShippedLanguages() {
                // A file from before French and Italian shipped gains them,
                // switched off, once (#81). Never written over a file with
                // problems; if the write fails they are still offered now.
                configuration = added
                try? store.save(added)
            }
            self.store = store
            self.configuration = configuration
            self.problems = problems
            self.isFallback = !result.problems.isEmpty
            self.fileProblems = Self.summaries(result.problems)
            self.fileExistedAtLaunch = loaded.fileFound
        } catch {
            self.store = nil
            var fallback = Configuration.default
            // Not a fresh install either (see fileExistedAtLaunch).
            fallback.modelServer = nil
            self.configuration = fallback
            self.problems = ["using defaults - \(Self.describe(error))"]
            self.isFallback = true
            self.fileProblems = self.problems
            self.fileExistedAtLaunch = true
        }
    }

    /// Re-reads the file. Problems replace the previous ones, so a save that
    /// fixes the file clears them.
    func reload() {
        guard let store else { return }
        // One read for both presence and content: an editor that deletes
        // and rewrites must never make a vanished file look like a clean
        // load of the defaults.
        let loaded = store.load()
        let result = ConfigurationReload.apply(
            previous: configuration, loaded: loaded, fileExists: loaded.fileFound, isLaunch: false)
        configuration = result.configuration
        problems = Self.summaries(result.problems)
        fileProblems = problems
        if result.problems.isEmpty { isFallback = false }
    }

    private static func summaries(_ problems: [ConfigurationProblem]) -> [String] {
        problems.map(\.summary)
    }

    /// "the configuration folder is inside an iCloud-synced location", or the
    /// system's own description for anything else.
    private static func describe(_ error: any Error) -> String {
        if let storageError = error as? StorageLocationError {
            switch storageError {
            case .iCloudSynced:
                return "the configuration folder is inside an iCloud-synced location"
            case .notAbsolute:
                return "the configuration path is not valid"
            }
        }
        return error.localizedDescription
    }
}
