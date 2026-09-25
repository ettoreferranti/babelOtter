import BabelOtterKit
import Foundation

/// Configuration and the Ollama client, built once at launch.
struct AppEnvironment: Sendable {

    let configuration: Configuration
    let configurationProblems: [ConfigurationProblem]
    let client: OllamaClient

    /// Reads `~/Library/Application Support/ch.babelotter/config.json`, and
    /// writes the defaults there on first launch so the glossary and
    /// do-not-translate list can be edited by hand until settings exist (M3).
    static func load() -> AppEnvironment {
        let home = FileManager.default.homeDirectoryForCurrentUser
        // NFR-P7: the directories iCloud Drive can sync on this machine.
        let locator = StorageLocator(
            home: home,
            iCloudRoots: ["Library/Mobile Documents", "Documents", "Desktop"]
                .map { home.appending(path: $0) })

        var configuration = Configuration.default
        var problems: [ConfigurationProblem] = []
        if let store = try? ConfigurationStore.inApplicationSupport(locator: locator) {
            let loaded = store.load()
            configuration = loaded.configuration
            problems = loaded.problems
            if !FileManager.default.fileExists(atPath: store.fileURL.path) {
                try? store.save(configuration)
            }
        }
        return AppEnvironment(
            configuration: configuration,
            configurationProblems: problems,
            client: OllamaClient.loopback(timeout: configuration.timeoutSeconds))
    }
}
