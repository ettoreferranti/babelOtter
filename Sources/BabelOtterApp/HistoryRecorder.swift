import BabelOtterKit
import Foundation

/// Opens history once at launch and writes each popup's record (#67); the
/// History window reads the same store (#68).
///
/// A store that cannot be opened leaves history off for the session; a write
/// that fails loses that record. Either way `problem` says why, for the menu,
/// and every action keeps working. No record text reaches a log.
@MainActor
final class HistoryRecorder {

    /// Nil when it could not be opened; `unavailableReason` then says why.
    let store: (any HistoryStore)?
    /// Why the store could not be opened, worded to follow "History is not
    /// saved - " in the window.
    let unavailableReason: String?
    /// The menu's whole line; nil while history works.
    private(set) var problem: String?
    /// The problem changed: the menu shows it.
    var onChange: (@MainActor () -> Void)?
    /// A record was saved: an open History window shows it.
    var onRecord: (@MainActor () -> Void)?

    init() {
        do {
            store = try SQLiteHistoryStore.inApplicationSupport(locator: AppStorage.locator())
            unavailableReason = nil
            problem = nil
        } catch {
            store = nil
            let reason = HistoryProblem.opening(error)
            unavailableReason = reason
            problem = HistoryProblem.notSaved(reason)
        }
    }

    func record(_ record: HistoryRecord) {
        guard let store else { return }
        let before = problem
        do {
            _ = try store.add(record)
            problem = nil
        } catch {
            problem = HistoryProblem.notSaved(HistoryProblem.saving(error))
        }
        if problem != before { onChange?() }
        if problem == nil { onRecord?() }
    }
}
