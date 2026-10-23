import BabelOtterKit
import Foundation

/// The target last chosen for each source language (#81), in the app's
/// preferences: language codes only, never text, and never `config.json`,
/// which the user may be editing by hand.
@MainActor
struct TargetMemory {

    private static let key = "targetBySource"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var remembered: [LanguageCode: LanguageCode] {
        TargetChoice.memory(from: stored)
    }

    func remember(_ direction: Direction) {
        defaults.set(TargetChoice.remembering(direction.target, for: direction.source, in: stored), forKey: Self.key)
    }

    private var stored: [String: String] {
        defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }
}
