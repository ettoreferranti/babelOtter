import Foundation
import Testing

@testable import BabelOtterKit

@Suite("Why history is not saved, in a few words")
struct HistoryProblemTests {

    @Test("a database that cannot be opened names SQLite's reason")
    func cannotOpen() {
        #expect(HistoryProblem.opening(HistoryStoreError.cannotOpen("file is not a database"))
            == "could not open the database (file is not a database)")
        #expect(HistoryProblem.opening(HistoryStoreError.statementFailed("disk I/O error"))
            == "could not open the database (disk I/O error)")
    }

    @Test("a newer database names its version")
    func newer() {
        #expect(HistoryProblem.opening(HistoryStoreError.newerSchema(3))
            == "the database was written by a newer lingoSwen (version 3)")
    }

    @Test("a refused folder says why")
    func refusedFolder() {
        let url = URL(filePath: "/Users/x/Documents/h")
        #expect(HistoryProblem.opening(StorageLocationError.iCloudSynced(url))
            == "its folder syncs to iCloud")
        #expect(HistoryProblem.opening(StorageLocationError.notAbsolute(url))
            == "its folder is not an absolute path")
    }

    @Test("a failed write names SQLite's reason")
    func saving() {
        #expect(HistoryProblem.saving(HistoryStoreError.statementFailed("database is locked"))
            == "could not save (database is locked)")
    }

    @Test("a failed read names SQLite's reason, or the error's description")
    func reading() {
        #expect(HistoryProblem.reading(HistoryStoreError.statementFailed("disk I/O error"))
            == "could not read (disk I/O error)")
        let error = CocoaError(.fileReadNoPermission)
        #expect(HistoryProblem.reading(error) == "could not read (\(error.localizedDescription))")
    }

    @Test("any other error falls back to its description")
    func other() {
        let error = CocoaError(.fileWriteNoPermission)
        #expect(HistoryProblem.opening(error)
            == "could not open the database (\(error.localizedDescription))")
        #expect(HistoryProblem.saving(error)
            == "could not save (\(error.localizedDescription))")
    }
}
