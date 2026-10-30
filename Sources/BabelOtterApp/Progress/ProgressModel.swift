import BabelOtterKit
import Foundation
import Observation

/// The Progress window's state (#78): History's corrections, read once per
/// opening and on every saved record, and the report for the language and
/// period chosen.
@MainActor
@Observable
final class ProgressModel {

    private static let languageKey = "progress.language"

    private(set) var corrections: [CorrectionStats] = []
    private(set) var languages: [LanguageCode] = []
    private(set) var loadProblem: String?
    var period: ProgressPeriod = .month
    /// Shown; `choose(_:)` is the user's pick, which alone is remembered,
    /// so a language with nothing in the loaded days does not lose it.
    private(set) var language: LanguageCode?

    func choose(_ code: LanguageCode?) {
        language = code
        guard let code else { return }
        UserDefaults.standard.set(code.rawValue, forKey: Self.languageKey)
    }

    private let store: (any HistoryStore)?
    private let unavailable: String?
    private let policy: @MainActor () -> HistoryPolicy
    private let configuration: @MainActor () -> Configuration

    init(
        store: (any HistoryStore)?, unavailable: String?,
        policy: @escaping @MainActor () -> HistoryPolicy,
        configuration: @escaping @MainActor () -> Configuration
    ) {
        self.store = store
        self.unavailable = unavailable
        self.policy = policy
        self.configuration = configuration
    }

    /// Two of the longest periods back: the period and the one before it.
    func refresh() {
        guard let store else { return }
        let longest = TimeInterval(ProgressPeriod.quarter.days) * 86_400
        do {
            corrections = try store.corrections(since: Date().addingTimeInterval(-2 * longest))
            loadProblem = nil
        } catch {
            corrections = []
            loadProblem = HistoryProblem.opening(error)
        }
        languages = ProgressReport.languages(in: corrections)
        if let language, languages.contains(language) { return }
        let saved = UserDefaults.standard.string(forKey: Self.languageKey).map(LanguageCode.init)
        if let saved, languages.contains(saved) {
            language = saved
        } else {
            language = languages.first
        }
    }

    var report: ProgressReport? {
        guard let language else { return nil }
        return ProgressReport(corrections: corrections, language: language, period: period, now: Date())
    }

    /// Why the window cannot show anything, or must say History is off.
    var notice: String? {
        if let unavailable { return "History is not available: \(unavailable)." }
        if let loadProblem { return "History could not be read: \(loadProblem)." }
        if !policy().records { return "Progress needs History. Turn it on in Settings \u{203A} General." }
        return nil
    }

    /// Nothing to show and nothing wrong: the "no corrections yet" state.
    var isEmpty: Bool {
        guard unavailable == nil, loadProblem == nil else { return false }
        return languages.isEmpty
    }

    func displayName(_ code: LanguageCode) -> String {
        let configured = configuration().languages
        for language in configured where language.code.baseSubtag == code.baseSubtag {
            return language.displayName
        }
        return code.rawValue
    }
}
