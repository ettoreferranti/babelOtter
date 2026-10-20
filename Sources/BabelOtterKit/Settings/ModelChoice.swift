import Foundation

/// What the Models tab offers for one action (#60).
public struct ModelChoice: Equatable, Sendable {
    /// The installed models, sorted, with the configured one added when it
    /// is not installed -- so the pop-up always shows what is in use.
    public let options: [String]
    public let configured: String
    public let isInstalled: Bool

    public init(configured: String, installed: [String]) {
        self.configured = configured
        var names = Array(Set(installed)).sorted()
        isInstalled = names.contains(configured)
        if !isInstalled {
            names.append(configured)
            names.sort()
        }
        options = names
    }
}
