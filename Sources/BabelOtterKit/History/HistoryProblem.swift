import Foundation

/// What went wrong with history, in a few words (#67, #69). Never carries
/// record text.
public enum HistoryProblem {

    /// The menu's line for a reason from `opening` or `saving`.
    public static func notSaved(_ reason: String) -> String {
        "History: not saved - " + reason
    }

    /// The menu's line when old records could not be deleted (#69).
    public static func pruning(_ error: any Error) -> String {
        "History: old records not deleted - " + reason(error)
    }

    /// Worded to follow "Could not clear the history - " in the window (#69).
    public static func clearing(_ error: any Error) -> String {
        reason(error)
    }

    /// SQLite's message, or the error's description.
    private static func reason(_ error: any Error) -> String {
        if case .statementFailed(let message)? = error as? HistoryStoreError {
            return message
        }
        return error.localizedDescription
    }

    public static func opening(_ error: any Error) -> String {
        if let failure = error as? HistoryStoreError {
            return opening(failure)
        }
        if let refusal = error as? StorageLocationError {
            return refused(refusal)
        }
        return "could not open the database (\(error.localizedDescription))"
    }

    public static func saving(_ error: any Error) -> String {
        if case .statementFailed(let message)? = error as? HistoryStoreError {
            return "could not save (\(message))"
        }
        return "could not save (\(error.localizedDescription))"
    }

    /// Worded to follow "Could not read the history - " in the window (#68).
    public static func reading(_ error: any Error) -> String {
        if case .statementFailed(let message)? = error as? HistoryStoreError {
            return "could not read (\(message))"
        }
        return "could not read (\(error.localizedDescription))"
    }

    private static func opening(_ failure: HistoryStoreError) -> String {
        switch failure {
        case .cannotOpen(let message), .statementFailed(let message):
            return "could not open the database (\(message))"
        case .newerSchema(let version):
            return "the database was written by a newer lingoSwen (version \(version))"
        }
    }

    private static func refused(_ refusal: StorageLocationError) -> String {
        switch refusal {
        case .iCloudSynced:
            return "its folder syncs to iCloud"
        case .notAbsolute:
            return "its folder is not an absolute path"
        }
    }
}
