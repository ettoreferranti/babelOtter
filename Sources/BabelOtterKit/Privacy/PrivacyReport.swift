import Foundation

/// Facts of the build the Privacy panel shows (#72).
public enum BuildFacts {
    /// Third-party Swift packages linked into lingoSwen. A test keeps this
    /// equal to the package graph; CI checks the graph against
    /// Config/dependency-allowlist.txt on every change (`NFR-P6`).
    public static let thirdPartyPackages = 0
}

/// One line of the Privacy panel.
public struct PrivacyLine: Sendable, Equatable {
    public enum Mark: Sendable, Equatable {
        case ok
        case warning
        /// Could not be determined: never shown as safe.
        case unknown
    }

    public let title: String
    public let detail: String
    public let mark: Mark
    /// A command that fixes a warning, offered with Copy.
    public let remedy: String?
}

/// What the Privacy panel says (#72, #73, `FR-ONB-03`, `FR-ONB-04`). All
/// the wording is here, so it is tested; the app gathers the facts.
public enum PrivacyReport {

    public static let bindingFix = "launchctl setenv OLLAMA_HOST 127.0.0.1:11434"
    public static let clipboardNote =
        "Replace and Copy pass text through the clipboard, which Universal Clipboard "
        + "can carry to your other devices; see PRIVACY.md."

    /// `historyRefusal` is why the history folder is refused (inside
    /// iCloud), nil when it is accepted.
    public static func lines(
        endpoint: OllamaEndpoint, listening: ListeningExposure, historyFolder: String,
        historyRefusal: StorageLocationError?, history: HistoryPolicy,
        packages: Int = BuildFacts.thirdPartyPackages
    ) -> [PrivacyLine] {
        [
            PrivacyLine(
                title: "Model connection",
                detail: "\(endpoint.baseURL.absoluteString) - this Mac only (loopback).",
                mark: .ok, remedy: nil),
            listeningLine(listening),
            historyLine(historyFolder, historyRefusal, history),
            PrivacyLine(
                title: "Dependencies",
                detail: packagesText(packages) + "; checked against the allowlist on every change.",
                mark: .ok, remedy: nil),
            PrivacyLine(
                title: "Telemetry",
                detail: "No telemetry, analytics or crash reporting. Nothing is sent anywhere "
                    + "but the local model.",
                mark: .ok, remedy: nil),
        ]
    }

    static func listeningLine(_ listening: ListeningExposure) -> PrivacyLine {
        let title = "Ollama listens on"
        let risk = " Other devices on your network can use your Ollama and see what is sent to it."
        switch listening {
        case .loopbackOnly(let hosts):
            return PrivacyLine(
                title: title, detail: "This Mac only (\(hosts.joined(separator: ", "))).",
                mark: .ok, remedy: nil)
        case .exposed(let hosts, let everywhere):
            var reach = "This network"
            if everywhere { reach = "All networks" }
            return PrivacyLine(
                title: title, detail: "\(reach) (\(hosts.joined(separator: ", "))).\(risk)",
                mark: .warning, remedy: bindingFix)
        case .unknown:
            return PrivacyLine(
                title: title,
                detail: "Unknown: Ollama is not running, or macOS did not say. "
                    + "This is not a sign that it is safe.",
                mark: .unknown, remedy: nil)
        }
    }

    static func historyLine(
        _ folder: String, _ refusal: StorageLocationError?, _ policy: HistoryPolicy
    ) -> PrivacyLine {
        if refusal != nil {
            return PrivacyLine(
                title: "History", detail: "\(folder) is inside iCloud, so history is not saved.",
                mark: .warning, remedy: nil)
        }
        return PrivacyLine(
            title: "History", detail: "\(folder), outside iCloud. \(retention(policy))",
            mark: .ok, remedy: nil)
    }

    static func retention(_ policy: HistoryPolicy) -> String {
        switch policy {
        case .keep(.days(let days)):
            if days == 1 { return "Records are kept for 1 day." }
            return "Records are kept for \(days) days."
        case .keep(.unlimited):
            return "Records are kept until you clear them."
        case .keep(.off), .off:
            return "History is off."
        case .paused:
            return "History is paused until config.json is fixed."
        }
    }

    static func packagesText(_ count: Int) -> String {
        if count == 1 { return "1 third-party package" }
        return "\(count) third-party packages"
    }
}
