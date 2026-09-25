import BabelOtterKit
import Foundation

/// Configuration and the Ollama client, built once at launch.
struct AppEnvironment: Sendable {

    let configuration: Configuration
    let configurationProblems: [ConfigurationProblem]
    /// What to tell the user when `configuration` is not what is actually on
    /// disk -- the storage folder could not be prepared, the first-launch
    /// save failed, or the existing file had problems `load()` fell back
    /// past. `nil` when there is nothing to say. Never derived from user
    /// text: everything here describes the config file itself (NFR-P7,
    /// FR-CFG-03), never the content a user selected.
    let configurationNote: String?
    let client: OllamaClient

    /// Reads `~/Library/Application Support/ch.babelotter/config.json`, and
    /// writes the defaults there on first launch so the glossary and
    /// do-not-translate list can be edited by hand until settings exist (M3).
    ///
    /// Every failure here falls back to `Configuration.default` so the app
    /// still starts -- but silently is not the same as safely. NFR-P7 exists
    /// specifically to catch storage landing somewhere it can sync to
    /// iCloud, and a fallback nobody can see defeats that. `configurationNote`
    /// is what makes the fallback visible.
    static func load() -> AppEnvironment {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // NFR-P7: the directories iCloud Drive can sync on this machine.
        let locator = StorageLocator(
            home: home,
            iCloudRoots: ["Library/Mobile Documents", "Documents", "Desktop"]
                .map { home.appending(path: $0) })

        var configuration = Configuration.default
        var problems: [ConfigurationProblem] = []
        var note: String?

        do {
            let store = try ConfigurationStore.inApplicationSupport(locator: locator)
            let loaded = store.load()
            configuration = loaded.configuration
            problems = loaded.problems
            if !FileManager.default.fileExists(atPath: store.fileURL.path) {
                do {
                    try store.save(configuration)
                } catch {
                    note = "using defaults - could not write the configuration file (\(describe(error)))"
                }
            }
        } catch {
            note = "using defaults - could not prepare the configuration folder (\(describe(error)))"
        }

        if note == nil, !problems.isEmpty {
            note = summarize(problems)
        }

        return AppEnvironment(
            configuration: configuration,
            configurationProblems: problems,
            configurationNote: note,
            client: OllamaClient.loopback(timeout: configuration.timeoutSeconds))
    }

    /// "using defaults - the configuration folder is inside an iCloud-synced
    /// location", or the system's own description for anything else that can
    /// go wrong preparing or writing the file.
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

    /// "1 problem - config.json (retentionDays): expected Int, found
    /// something else", or the same shape with a count for more than one.
    /// Only the first is named -- FR-CFG-03 wants the fix pointed at, not an
    /// exhaustive list crowding a menu.
    private static func summarize(_ problems: [ConfigurationProblem]) -> String {
        let first = problems[0]
        let location = first.field.map { "\(first.file) (\($0))" } ?? first.file
        let firstDescription = "\(location): \(first.detail)"
        return problems.count == 1
            ? "1 problem - \(firstDescription)"
            : "\(problems.count) problems - \(firstDescription)"
    }
}
