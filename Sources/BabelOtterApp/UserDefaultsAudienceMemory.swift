import BabelOtterKit
import Foundation

/// `AudienceMemory` over UserDefaults: a dictionary of bundle ID to audience
/// id, and the last pick overall under the key the popup used before #52, so
/// an existing preference carries over. Ids only, never text.
final class UserDefaultsAudienceMemory: AudienceMemory {

    private static let perAppKey = "audienceByApp"
    private static let lastKey = "lastProfileID"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lastChoice(forApp bundleIdentifier: String) -> String? {
        perApp[bundleIdentifier]
    }

    func lastChoice() -> String? {
        defaults.string(forKey: Self.lastKey)
    }

    func remember(_ id: String, forApp bundleIdentifier: String?) {
        defaults.set(id, forKey: Self.lastKey)
        guard let bundleIdentifier else { return }
        var map = perApp
        map[bundleIdentifier] = id
        defaults.set(map, forKey: Self.perAppKey)
    }

    private var perApp: [String: String] {
        defaults.dictionary(forKey: Self.perAppKey) as? [String: String] ?? [:]
    }
}
