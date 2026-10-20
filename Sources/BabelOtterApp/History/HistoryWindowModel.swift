import BabelOtterKit
import Foundation

/// The History window's state, published for SwiftUI (#68). The paging and
/// searching are `HistoryBrowser`'s; this adds the search delay and the
/// selection.
@MainActor
final class HistoryWindowModel: ObservableObject {

    static let searchDelay = Duration.milliseconds(150)

    @Published private(set) var records: [HistoryRecord] = []
    @Published private(set) var hasMore = false
    @Published private(set) var problem: HistoryBrowserProblem?
    /// The term the list is filtered by; nil shows everything.
    @Published private(set) var term: String?
    /// What is typed in the search field; the list follows after a pause.
    @Published var query = "" {
        didSet { scheduleSearch() }
    }
    @Published var selection: Int64?
    /// "History is off - nothing new is saved.", while nothing is recorded.
    @Published private(set) var note: String?
    /// Bumped by Command-F; the view focuses the search field.
    @Published private(set) var searchFocusRequests = 0

    /// Asks before Clear All: the count when known, and what to run on Delete.
    var confirmClearAll: ((Int?, @escaping @MainActor () -> Void) -> Void)?

    private let browser: HistoryBrowser
    private let configuration: () -> Configuration
    private let policyNote: () -> String?
    private var pendingSearch: Task<Void, Never>?

    init(
        browser: HistoryBrowser, configuration: @escaping () -> Configuration,
        policyNote: @escaping () -> String?
    ) {
        self.browser = browser
        self.configuration = configuration
        self.policyNote = policyNote
        publish()
    }

    /// Nothing to delete, or no history to delete it from.
    var canClearAll: Bool {
        if case .unavailable = problem { return false }
        return !(records.isEmpty && term == nil)
    }

    func requestClearAll() {
        guard canClearAll else { return }
        confirmClearAll?(browser.count()) { [weak self] in
            guard let self else { return }
            if self.browser.clearAll() { self.selection = nil }
            self.publish()
        }
    }

    var selectedRecord: HistoryRecord? {
        guard let selection else { return nil }
        return records.first { $0.id == selection }
    }

    func row(_ record: HistoryRecord) -> HistoryRow {
        HistoryRow(record, configuration: configuration())
    }

    func loadMore() {
        browser.loadMore()
        publish()
    }

    /// A record was saved while the window is open.
    func refresh() {
        browser.refresh()
        publish()
    }

    func focusSearch() {
        searchFocusRequests += 1
    }

    private func scheduleSearch() {
        pendingSearch?.cancel()
        let wanted = query
        pendingSearch = Task { [weak self] in
            try? await Task.sleep(for: Self.searchDelay)
            guard !Task.isCancelled, let self else { return }
            self.browser.search(wanted)
            self.publish()
        }
    }

    /// The selection stays on its record while that record is listed.
    private func publish() {
        note = policyNote()
        records = browser.records
        hasMore = browser.hasMore
        problem = browser.problem
        term = browser.term
        if let selection, !records.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }
}
