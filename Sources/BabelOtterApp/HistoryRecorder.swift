import BabelOtterKit
import Foundation

/// Opens history once at launch and writes each popup's record (#67); the
/// History window reads the same store (#68); the policy decides whether to
/// record and what to prune (#69).
///
/// A store that cannot be opened leaves history off for the session; a write
/// that fails loses that record; a failed prune leaves old records for the
/// next try. Each way `problem` says why, for the menu, and every action
/// keeps working. No record text reaches a log.
@MainActor
final class HistoryRecorder {

    /// Nil when it could not be opened; `unavailableReason` then says why.
    let store: (any HistoryStore)?
    /// Why the store could not be opened, worded to follow "History is not
    /// saved - " in the window.
    let unavailableReason: String?
    /// Paused until the app applies the configuration's policy at launch.
    private(set) var policy = HistoryPolicy.paused
    /// The menu's whole line; nil while history works.
    var problem: String? { saveProblem ?? pruneProblem }
    /// The problem changed: the menu shows it.
    var onChange: (@MainActor () -> Void)?
    /// Records were saved or deleted: an open History window reloads.
    var onRecord: (@MainActor () -> Void)?

    /// Opening or the last write; a write that succeeds clears it.
    private var saveProblem: String?
    /// The last prune; a prune that succeeds clears it.
    private var pruneProblem: String?
    /// When Clear All last succeeded: a popup still open then holds a
    /// result from before it, which must not reappear after it.
    private var clearedAt: Date?

    init() {
        do {
            store = try SQLiteHistoryStore.inApplicationSupport(locator: AppStorage.locator())
            unavailableReason = nil
        } catch {
            store = nil
            let reason = HistoryProblem.opening(error)
            unavailableReason = reason
            saveProblem = HistoryProblem.notSaved(reason)
        }
    }

    /// At launch and after each reload of the configuration; prunes at once,
    /// so a shortened period applies without waiting for the next save.
    func apply(_ policy: HistoryPolicy) {
        self.policy = policy
        changing {
            // Nothing is written now, so an earlier failed write no longer
            // matters. A store that never opened keeps saying so.
            if !policy.records {
                if store != nil { saveProblem = nil }
            }
            prune()
        }
    }

    /// Clear All succeeded.
    func cleared() {
        clearedAt = Date()
    }

    func record(_ record: HistoryRecord) {
        guard let store else { return }
        guard policy.records else { return }
        if let clearedAt {
            if record.date < clearedAt { return }
        }
        changing {
            do {
                _ = try store.add(record)
                saveProblem = nil
            } catch {
                saveProblem = HistoryProblem.notSaved(HistoryProblem.saving(error))
                return
            }
            onRecord?()
            prune()
        }
    }

    private func prune() {
        guard let store else { return }
        guard let cutoff = policy.pruneCutoff(now: Date()) else {
            // Nothing prunes now, so an earlier failure no longer matters.
            pruneProblem = nil
            return
        }
        do {
            let deleted = try store.deleteOlder(than: cutoff)
            pruneProblem = nil
            if deleted > 0 { onRecord?() }
        } catch {
            pruneProblem = HistoryProblem.pruning(error)
        }
    }

    /// Runs `body`, then tells the menu if the problem line changed.
    private func changing(_ body: () -> Void) {
        let before = problem
        body()
        if problem != before { onChange?() }
    }
}
