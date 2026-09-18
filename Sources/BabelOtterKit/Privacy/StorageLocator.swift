import Foundation

public enum StorageLocationError: Error, Equatable {
    /// The path sits inside a tree that syncs to iCloud.
    case iCloudSynced(URL)
    /// The path is not absolute, so it cannot be reasoned about.
    case notAbsolute(URL)
}

/// Decides where babelOtter may keep data, and refuses anywhere that would
/// upload it.
///
/// NFR-P7. The synced roots are injected rather than detected inside this type,
/// so the boundary logic is pure and exhaustively testable; the app supplies the
/// real roots at start-up. On the target machine `~/Documents` is iCloud-synced,
/// which is exactly the case a hardcoded "just use Application Support" would
/// have got right by luck and a future refactor would have got wrong.
public struct StorageLocator: Sendable {

    public let home: URL
    public let iCloudRoots: [URL]

    public init(home: URL, iCloudRoots: [URL]) {
        self.home = home
        self.iCloudRoots = iCloudRoots
    }

    /// `~/Library/Application Support/ch.babelotter` — never validated here;
    /// callers pass the result to ``validate(_:)`` or ``prepare(_:)``.
    public func applicationSupportDirectory() throws -> URL {
        home
            .appending(path: "Library/Application Support")
            .appending(path: BabelOtter.bundleIdentifier)
    }

    /// Throws if `candidate` is relative, or sits at or beneath a synced root.
    public func validate(_ candidate: URL) throws {
        let path = Self.normalized(candidate)
        guard path.hasPrefix("/") else {
            throw StorageLocationError.notAbsolute(candidate)
        }
        for root in iCloudRoots {
            let rootPath = Self.normalized(root)
            // Compare on component boundaries: "/Users/x/DocumentsArchive" is not
            // inside "/Users/x/Documents", though a bare hasPrefix says it is.
            if path == rootPath || path.hasPrefix(rootPath + "/") {
                throw StorageLocationError.iCloudSynced(candidate)
            }
        }
    }

    /// Validates, creates if needed, then locks down: owner-only access and
    /// excluded from backup.
    public func prepare(_ directory: URL) throws {
        try validate(directory)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path(percentEncoded: false)
        )

        var mutable = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutable.setResourceValues(values)
    }

    private static func normalized(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
