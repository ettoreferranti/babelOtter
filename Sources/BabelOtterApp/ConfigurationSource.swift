import BabelOtterKit
import Foundation

/// Where the configuration comes from, and what is wrong with it.
///
/// Reads `~/Library/Application Support/ch.babelotter/config.json`, writing
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

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // NFR-P7: the directories iCloud Drive can sync on this machine.
        let locator = StorageLocator(
            home: home,
            iCloudRoots: ["Library/Mobile Documents", "Documents", "Desktop"]
                .map { home.appending(path: $0) })
        do {
            let store = try ConfigurationStore.inApplicationSupport(locator: locator)
            let loaded = store.load()
            let result = ConfigurationReload.apply(
                previous: .default, loaded: loaded, fileExists: loaded.fileFound, isLaunch: true)
            var problems = Self.summaries(result.problems)
            if !loaded.fileFound {
                do {
                    try store.save(result.configuration)
                } catch {
                    problems += ["using defaults - could not write the file (\(error.localizedDescription))"]
                }
            }
            self.store = store
            self.configuration = result.configuration
            self.problems = problems
        } catch {
            self.store = nil
            self.configuration = .default
            self.problems = ["using defaults - \(Self.describe(error))"]
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
