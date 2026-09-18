import Foundation

/// Integration tests run locally only. CI runners have no Ollama and no models,
/// and this repository is public — nothing resembling real user text should ever
/// execute on a third-party runner. See NFR-P8.
///
/// Enable locally with:  BABELOTTER_INTEGRATION=1 swift test
enum IntegrationGate {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["BABELOTTER_INTEGRATION"] == "1"
    }
}
