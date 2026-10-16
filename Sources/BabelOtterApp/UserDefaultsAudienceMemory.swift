import BabelOtterKit
import Foundation

/// `AudienceMemory` over UserDefaults: a dictionary of bundle ID to audience
/// id, and the last pick overall under the key the popup used before #52, so
/// an existing preference carries over. Ids only, never text.
final class UserDefaultsAudienceMemory: AudienceMemory {

    private let perAppKey: String
    private let lastKey: String
    private let defaults: UserDefaults

    /// `prefix` keeps one action's choices apart from another's: Re-pitch
    /// uses "repitch." (#66). Translate and Correct keep the keys from before
    /// #52, so an existing preference carries over.
    init(prefix: String = "", defaults: UserDefaults = .standard) {
        perAppKey = prefix + "audienceByApp"
        lastKey = prefix + "lastProfileID"
        self.defaults = defaults
    }

    func lastChoice(forApp bundleIdentifier: String) -> String? {
        perApp[bundleIdentifier]
    }

    func lastChoice() -> String? {
        defaults.string(forKey: lastKey)
    }

    func remember(_ id: String, forApp bundleIdentifier: String?) {
        defaults.set(id, forKey: lastKey)
        guard let bundleIdentifier else { return }
        var map = perApp
        map[bundleIdentifier] = id
        defaults.set(map, forKey: perAppKey)
    }

    private var perApp: [String: String] {
        defaults.dictionary(forKey: perAppKey) as? [String: String] ?? [:]
    }
}
