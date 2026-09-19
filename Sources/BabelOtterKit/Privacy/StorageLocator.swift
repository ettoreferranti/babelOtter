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

    /// Resolves a path as far as the filesystem currently allows — see
    /// ``resolveAsFarAsExists(_:exists:resolveSymlinks:)``. Injectable so the
    /// path-boundary comparison in ``validate(_:)`` stays a pure string
    /// operation, testable without touching disk; production code gets the
    /// real filesystem via the default.
    private let resolve: @Sendable (URL) -> URL

    public init(
        home: URL,
        iCloudRoots: [URL],
        resolve: @escaping @Sendable (URL) -> URL = StorageLocator.resolveUsingRealFilesystem
    ) {
        self.home = home
        self.iCloudRoots = iCloudRoots
        self.resolve = resolve
    }

    /// `~/Library/Application Support/ch.babelotter` — never validated here;
    /// callers pass the result to ``validate(_:)`` or ``prepare(_:)``.
    ///
    /// Deliberately non-throwing: the body is pure URL appending and has no
    /// failure mode. It was declared `throws` and could not throw, which in
    /// the one type standing between the user's history and iCloud reads as
    /// "this checks something" when it checks nothing. ``validate(_:)`` and
    /// ``prepare(_:)`` are where the refusal lives; this only names a path.
    public func applicationSupportDirectory() -> URL {
        home
            .appending(path: "Library/Application Support")
            .appending(path: BabelOtter.bundleIdentifier)
    }

    /// Throws if `candidate` is relative, or sits at or beneath a synced root.
    ///
    /// Two choices here are deliberately conservative, in the same direction
    /// both times: a wrongly *refused* path fails loudly and is fixed in
    /// minutes; a wrongly *accepted* one silently uploads the user's writing
    /// and nobody ever finds out. Given that asymmetry, over-refusing is the
    /// safe failure mode.
    ///
    /// - The comparison is case-insensitive. macOS volumes are
    ///   case-insensitive (case-preserving) by default, so `~/documents` and
    ///   `~/Documents` name the same directory on disk even though they are
    ///   different `String`s. On a case-*sensitive* volume this can refuse a
    ///   path that is genuinely distinct from any synced root — accepted
    ///   deliberately, in this direction, on purpose.
    /// - Both `candidate` and every root are run through ``resolve`` — which
    ///   walks up to the deepest existing ancestor and resolves symlinks
    ///   there — before comparing. Without this, a symlink planted at or
    ///   above the candidate (e.g. `~/Library/Application
    ///   Support/ch.babelotter` replaced with a symlink into `~/Documents`,
    ///   or `~/Documents` itself being a symlink into `~/Library/Mobile
    ///   Documents/...`, which is exactly what Desktop & Documents sync does)
    ///   would dodge a purely lexical comparison. Both sides are resolved,
    ///   not just the candidate: resolving only one would just move the
    ///   mismatch rather than close it.
    public func validate(_ candidate: URL) throws {
        let path = Self.normalized(candidate)
        guard path.hasPrefix("/") else {
            throw StorageLocationError.notAbsolute(candidate)
        }

        let resolvedCandidate = Self.caseFolded(Self.normalized(resolve(candidate)))
        for root in iCloudRoots {
            let resolvedRoot = Self.caseFolded(Self.normalized(resolve(root)))
            // Compare on component boundaries: "/users/x/documentsarchive" is not
            // inside "/users/x/documents", though a bare hasPrefix says it is.
            if resolvedCandidate == resolvedRoot || resolvedCandidate.hasPrefix(resolvedRoot + "/") {
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

    /// Case-folds for comparison only. Never used for display, for a
    /// filesystem call, or for anything in `StorageLocationError` — those
    /// keep the original, case-preserved URL.
    private static func caseFolded(_ path: String) -> String {
        path.lowercased()
    }

    /// The real-filesystem wiring for ``resolve``, and the default for
    /// ``init(home:iCloudRoots:resolve:)``. `public` only because a default
    /// argument value on a `public` initializer must be at least as visible
    /// as the initializer itself — this is not meant to be called directly.
    public static func resolveUsingRealFilesystem(_ url: URL) -> URL {
        resolveAsFarAsExists(
            url,
            exists: { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) },
            resolveSymlinks: { $0.resolvingSymlinksInPath() }
        )
    }

    /// Walks `url` from its full path upward to the deepest ancestor that
    /// `exists` reports as present right now, resolves symlinks on that one
    /// ancestor with `resolveSymlinks`, then re-appends the remaining —
    /// necessarily non-existent — components underneath the resolved
    /// ancestor.
    ///
    /// This exists because the real `resolveSymlinks`
    /// (`URL.resolvingSymlinksInPath()`) is a no-op on anything that does not
    /// exist yet, and `validate()`/`prepare()` are always called before the
    /// path they check exists — that ordering is the entire point of
    /// `prepare()` (validate, then create). Calling `resolveSymlinks` on the
    /// full candidate directly is therefore a no-op in exactly the situation
    /// that matters: a symlinked ancestor with a not-yet-created leaf
    /// underneath it would sail through unresolved.
    ///
    /// Given `exists`/`resolveSymlinks` as parameters (rather than reaching
    /// for `FileManager`/`URL` directly) so this algorithm is unit-testable
    /// against fake filesystem state, with no real disk involved — see
    /// `internal` visibility, used by the test target via `@testable import`.
    static func resolveAsFarAsExists(
        _ url: URL,
        exists: (URL) -> Bool,
        resolveSymlinks: (URL) -> URL
    ) -> URL {
        // Built from pathComponents, not repeated `deletingLastPathComponent()`,
        // because that method infers a directory hint and leaves a trailing
        // slash on every intermediate ancestor's `.path` — harmless for real
        // FileManager calls, but it would make `exists`/`resolveSymlinks` see
        // an inconsistent path shape depending on how deep the walk goes.
        var components = url.standardizedFileURL.pathComponents
        var remainder: [String] = []

        while components.count > 1, !exists(Self.url(fromPathComponents: components)) {
            remainder.insert(components.removeLast(), at: 0)
        }

        let ancestor = Self.url(fromPathComponents: components)
        let resolvedAncestor = exists(ancestor) ? resolveSymlinks(ancestor) : ancestor
        return remainder.reduce(resolvedAncestor) { $0.appending(path: $1) }
    }

    private static func url(fromPathComponents components: [String]) -> URL {
        guard let first = components.first else { return URL(filePath: "/") }
        var result = URL(filePath: first == "/" ? "/" : first)
        for component in components.dropFirst() {
            result = result.appending(path: component)
        }
        return result
    }
}
