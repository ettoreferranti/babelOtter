import Foundation

/// The Ollama bundled in the app, and how lingoSwen runs it (#126).
///
/// Everything here is a value, so the exact command, environment and file
/// locations are tested; `BuiltInServerController` in the app only runs it.
public enum BuiltInServer {

    /// The model the built-in server downloads and every action uses.
    public static let model = Configuration.defaultModel
    public static let modelDisplayName = "Mistral Small 3.2"
    /// What the download screen promises, rounded as Ollama's library shows it.
    public static let downloadSizeText = "15 GB"

    /// How long a loaded model stays in memory after its last request: through
    /// a working session, but not all day (it holds about 19 GB).
    public static let keepAlive = "30m"

    /// Only these are passed on from lingoSwen's own environment; anything
    /// else (an `OLLAMA_HOST` or `OLLAMA_DEBUG` set for the user's own
    /// Ollama, say) must not reach the bundled one. `HOME` is not among
    /// them: the server gets its own (see `BuiltInServerFiles.home`).
    static let inheritedVariables = ["PATH"]
}

/// Where the built-in server's files live, under lingoSwen's Application
/// Support folder.
public struct BuiltInServerFiles: Sendable, Equatable {
    public let directory: URL

    public init(supportDirectory: URL) {
        directory = supportDirectory.appending(path: "ollama", directoryHint: .isDirectory)
    }

    /// Never `~/.ollama/models`: two servers writing one store can corrupt
    /// it, and removing lingoSwen's models must not touch the user's.
    public var models: URL { directory.appending(path: "models", directoryHint: .isDirectory) }
    /// The server's `HOME`. Ollama keeps state under `~/.ollama` (its key,
    /// among others): the built-in server keeps it here, never in the
    /// user's own.
    public var home: URL { directory.appending(path: "home", directoryHint: .isDirectory) }
    public var pidFile: URL { directory.appending(path: "server.pid") }
    /// Emptied at each start.
    public var log: URL { directory.appending(path: "server.log") }
}

/// The command that starts the built-in server.
public struct BuiltInServerLaunch: Sendable, Equatable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]

    /// `resources` is the app bundle's `Contents/Resources`; the official
    /// macOS build is unpacked, unchanged, into its `ollama` folder.
    public init(resources: URL, files: BuiltInServerFiles, inherited: [String: String]) {
        executable = resources.appending(path: "ollama", directoryHint: .isDirectory).appending(path: "ollama")
        arguments = ["serve"]
        var environment: [String: String] = [:]
        for name in BuiltInServer.inheritedVariables {
            if let value = inherited[name] { environment[name] = value }
        }
        environment["HOME"] = files.home.path(percentEncoded: false)
        let endpoint = OllamaEndpoint.builtIn
        environment["OLLAMA_HOST"] = "\(endpoint.host):\(endpoint.port)"
        environment["OLLAMA_MODELS"] = files.models.path(percentEncoded: false)
        environment["OLLAMA_KEEP_ALIVE"] = BuiltInServer.keepAlive
        environment["OLLAMA_NO_CLOUD"] = "1"
        self.environment = environment
    }
}
