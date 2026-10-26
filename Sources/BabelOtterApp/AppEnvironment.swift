import BabelOtterKit
import Foundation

/// The configuration in use and the Ollama client built from it.
///
/// Rebuilt on every reload (#26). A popup takes the environment when it
/// opens and keeps it, so a save never changes a request already running.
struct AppEnvironment: Sendable {
    let configuration: Configuration
    let client: OllamaClient

    init(configuration: Configuration) {
        self.configuration = configuration
        client = OllamaClient.loopback(configuration.endpoint, timeout: configuration.timeoutSeconds)
    }
}
