import BabelOtterKit
import Foundation
import Observation

/// The learning goal's state (#136): the log, kept in the app's
/// preferences as JSON -- days, totals and milestones, never text -- and
/// `LearningRules` applied to each saved record.
///
/// A popup saves its record when it closes, so what it shows under a
/// result is a preview: the same rules on the log as it is, without
/// changing it.
@MainActor
@Observable
final class LearningTracker {

    private static let key = "learning.log"
    /// The 30 days "tamed" looks at, the 30 before, and a day to spare.
    private static let lookBack: TimeInterval = 61 * 86_400

    private(set) var log: LearningLog

    private let defaults: UserDefaults
    private let store: (any HistoryStore)?
    private let policy: @MainActor () -> HistoryPolicy
    private let configuration: @MainActor () -> Configuration

    init(
        store: (any HistoryStore)?,
        policy: @escaping @MainActor () -> HistoryPolicy,
        configuration: @escaping @MainActor () -> Configuration,
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.policy = policy
        self.configuration = configuration
        self.defaults = defaults
        log = Self.load(from: defaults)
    }

    var settings: LearningSettings { configuration().learningSettings }

    /// The switch is on and History records: the game needs both.
    var isCounting: Bool {
        guard settings.enabled, store != nil else { return false }
        return policy().records
    }

    func week(now: Date = Date()) -> LearningWeek {
        LearningRules.week(log, goal: settings.daysPerWeek, now: now, calendar: .current)
    }

    /// The line a popup shows under a finished Correct or Explain: what
    /// saving `record` will do. Changes nothing.
    func preview(_ record: HistoryRecord) -> String? {
        guard isCounting else { return nil }
        return outcome(of: record, isSaved: false)?.line
    }

    /// History saved `record`.
    func saved(_ record: HistoryRecord) {
        guard settings.enabled else { return }
        guard let outcome = outcome(of: record, isSaved: true) else { return }
        log = outcome.log
        save()
    }

    /// The hint under a finished translation, at most one a day; showing
    /// it is what uses the day up.
    func hint(for direction: Direction, words: Int) -> String? {
        guard isCounting else { return nil }
        let configuration = configuration()
        let today = LearningDay(Date(), calendar: .current)
        let hint = TranslateHint.hint(
            for: direction, myLanguage: configuration.myLanguageCode, words: words,
            lastHintDay: log.lastHintDay, today: today)
        guard let hint else { return nil }
        log.hintShown(on: today)
        save()
        return hint.text(
            languages: configuration.languages,
            hotKey: TranslateHint.hotKey(for: hint.action, in: configuration.hotkeys))
    }

    func reset() {
        log = LearningLog()
        save()
    }

    private func outcome(of record: HistoryRecord, isSaved: Bool) -> LearningOutcome? {
        let configuration = configuration()
        let context = LearningContext(
            goal: configuration.learningSettings.daysPerWeek, myLanguage: configuration.myLanguageCode,
            languages: configuration.languages, calendar: .current,
            corrections: corrections(around: record, isSaved: isSaved))
        return LearningRules.outcome(of: record, log: log, context: context)
    }

    /// History's recent corrections, for "tamed"; the record's own among
    /// them, which History only has once it is saved. A read that fails
    /// earns nothing and loses nothing else.
    private func corrections(around record: HistoryRecord, isSaved: Bool) -> [CorrectionStats] {
        guard record.action == .correct, let store else { return [] }
        var found = (try? store.corrections(since: record.date.addingTimeInterval(-Self.lookBack))) ?? []
        if !isSaved, let words = record.wordCount {
            found.append(CorrectionStats(
                date: record.date, language: record.sourceLanguage, wordCount: words,
                mistakes: record.mistakes))
        }
        return found
    }

    private static func load(from defaults: UserDefaults) -> LearningLog {
        guard let data = defaults.data(forKey: key) else { return LearningLog() }
        return (try? JSONDecoder().decode(LearningLog.self, from: data)) ?? LearningLog()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(log) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
