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

    /// Nil when it could not be opened; `problem` then says why.
    let store: (any HistoryStore)?
    /// Worded to follow "History: not saved - "; nil while history works.
    private(set) var problem: String?
    /// The problem changed: the menu shows it.
    var onChange: (@MainActor () -> Void)?
    /// A record was saved: an open History window shows it.
    var onRecord: (@MainActor () -> Void)?

    init() {
        do {
            store = try SQLiteHistoryStore.inApplicationSupport(locator: AppStorage.locator())
            problem = nil
        } catch {
            store = nil
            problem = HistoryProblem.opening(error)
        }
    }

    func record(_ record: HistoryRecord) {
        guard let store else { return }
        let before = problem
        do {
            _ = try store.add(record)
            problem = nil
        } catch {
            problem = HistoryProblem.saving(error)
        }
        if problem != before { onChange?() }
        if problem == nil { onRecord?() }
    }
}
