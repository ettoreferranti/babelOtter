import Testing
import Foundation
@testable import BabelOtterKit

/// NFR-P7: local storage must sit outside every iCloud-synced tree. On the
/// target machine ~/Documents *is* iCloud-synced, so a naive Application
/// Support fallback is not enough — the path is validated, not assumed.
@Suite("StorageLocator refuses synced locations")
struct StorageLocatorTests {

    let home = URL(filePath: "/Users/example")

    var locator: StorageLocator {
        StorageLocator(
            home: home,
            iCloudRoots: [
                URL(filePath: "/Users/example/Library/Mobile Documents"),
                URL(filePath: "/Users/example/Documents"),
                URL(filePath: "/Users/example/Desktop"),
            ]
        )
    }

    @Test("rejects a path inside an iCloud-synced tree", arguments: [
        "/Users/example/Documents/history.sqlite",
        "/Users/example/Documents/nested/deep/history.sqlite",
        "/Users/example/Desktop/history.sqlite",
        "/Users/example/Library/Mobile Documents/com~apple~CloudDocs/history.sqlite",
    ])
    func rejectsSyncedPaths(path: String) {
        let candidate = URL(filePath: path)
        #expect(throws: StorageLocationError.iCloudSynced(candidate)) {
            try locator.validate(candidate)
        }
    }

    @Test("rejects the synced root itself")
    func rejectsSyncedRoot() {
        let candidate = URL(filePath: "/Users/example/Documents")
        #expect(throws: StorageLocationError.self) { try locator.validate(candidate) }
    }

    @Test("accepts paths outside every synced tree", arguments: [
        "/Users/example/Library/Application Support/ch.babelotter/history.sqlite",
        "/Users/example/.babelotter/history.sqlite",
    ])
    func acceptsSafePaths(path: String) throws {
        try locator.validate(URL(filePath: path))
    }

    /// The classic prefix bug: "/Users/example/DocumentsArchive" is not inside
    /// "/Users/example/Documents", and a naive hasPrefix check says it is.
    @Test("does not reject a sibling whose name merely starts the same", arguments: [
        "/Users/example/DocumentsArchive/history.sqlite",
        "/Users/example/Documents-old/history.sqlite",
        "/Users/example/DesktopBackup/history.sqlite",
    ])
    func respectsPathComponentBoundaries(path: String) throws {
        try locator.validate(URL(filePath: path))
    }

    @Test("rejects relative paths")
    func rejectsRelativePaths() {
        // Deviation from the brief, disclosed in the Task 9 report: the brief used
        // `URL(filePath: "relative/history.sqlite")`, but that initializer (like
        // `URL(fileURLWithPath:)`) resolves a relative-looking string against the
        // process's current working directory at construction time — even the raw
        // `.path`, before any `standardizedFileURL` call, is already absolute. So
        // `StorageLocationError.notAbsolute` can never be observed through that
        // construction; the assertion would fail on every toolchain, not just this
        // one. `URL(string:)` with no scheme is the construction that actually
        // yields a non-file URL with a genuinely relative `.path`, which is the
        // only realistic way a caller could hand `validate(_:)` a non-absolute URL.
        let candidate = URL(string: "relative/history.sqlite")!
        #expect(throws: StorageLocationError.self) { try locator.validate(candidate) }
    }

    @Test("resolves Application Support under the bundle identifier")
    func resolvesApplicationSupport() throws {
        let directory = try locator.applicationSupportDirectory()
        #expect(directory.path(percentEncoded: false)
            == "/Users/example/Library/Application Support/ch.babelotter")
    }

    @Test("prepare creates the directory with owner-only permissions")
    func prepareSetsPermissions() throws {
        let sandbox = URL(filePath: NSTemporaryDirectory())
            .appending(path: "babelotter-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let real = StorageLocator(home: sandbox, iCloudRoots: [])
        let directory = try real.applicationSupportDirectory()
        try real.prepare(directory)

        let attributes = try FileManager.default
            .attributesOfItem(atPath: directory.path(percentEncoded: false))
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.int16Value == 0o700)

        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("prepare refuses a synced directory")
    func prepareRefusesSyncedDirectory() {
        let synced = URL(filePath: "/Users/example/Documents/ch.babelotter")
        #expect(throws: StorageLocationError.self) { try locator.prepare(synced) }
    }

    // MARK: - Fix round 1, Q1: case-insensitive volumes (Refs #24)
    //
    // macOS volumes are case-insensitive (case-preserving) by default: creating
    // "Documents" makes "documents" resolve to the same directory on disk. A
    // bare, case-sensitive `hasPrefix` missed that — confirmed directly against
    // this type before the fix (see the Task 9 report's "Fix round 1" section
    // for the real before/after command output). The fix folds case before
    // comparing; these tests exercise that, plus a check that folding didn't
    // turn the comparison into a substring match.

    @Test("rejects a synced path spelled in a different case", arguments: [
        "/Users/example/documents/history.sqlite",
        "/Users/example/DoCuMeNtS/history.sqlite",
        "/Users/example/DOCUMENTS/nested/history.sqlite",
    ])
    func rejectsSyncedPathsRegardlessOfCase(path: String) {
        let candidate = URL(filePath: path)
        #expect(throws: StorageLocationError.self) { try locator.validate(candidate) }
    }

    @Test("case-insensitive comparison does not become a substring match", arguments: [
        "/Users/example/documentsarchive/history.sqlite",
        "/Users/example/DOCUMENTS-OLD/history.sqlite",
        "/Users/example/desktopbackup/history.sqlite",
    ])
    func caseFoldingRespectsPathComponentBoundaries(path: String) throws {
        try locator.validate(URL(filePath: path))
    }

    // MARK: - Fix round 1, Q2: symlink resolution (Refs #24)
    //
    // `standardizedFileURL` never resolves symlinks, so a symlink planted at or
    // above the candidate lexically dodges a purely string-based comparison —
    // confirmed directly against this type before the fix (see the report).
    // The fix resolves both the candidate and every root as far as the
    // filesystem currently allows before comparing. These are real end-to-end
    // tests against real symlinks on disk — the pure comparison logic above
    // stays disk-free; only this section touches the filesystem.

    /// A sandbox with a real `Documents` directory, cleaned up after the test.
    private func makeSandbox() throws -> URL {
        let sandbox = URL(filePath: NSTemporaryDirectory())
            .appending(path: "babelotter-symlink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: sandbox.appending(path: "Documents"),
            withIntermediateDirectories: true
        )
        return sandbox
    }

    @Test("rejects a leaf directory that is itself a symlink into Documents, with the file absent")
    func rejectsSymlinkedLeafIntoDocuments() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let hidden = sandbox.appending(path: "Documents/hidden-history-store")
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)

        let appSupportParent = sandbox.appending(path: "Library/Application Support")
        try FileManager.default.createDirectory(at: appSupportParent, withIntermediateDirectories: true)
        let appSupportBabelotter = appSupportParent.appending(path: "ch.babelotter")
        try FileManager.default.createSymbolicLink(at: appSupportBabelotter, withDestinationURL: hidden)

        let sandboxLocator = StorageLocator(home: sandbox, iCloudRoots: [sandbox.appending(path: "Documents")])
        // The leaf file does not exist — this is the state validate()/prepare()
        // always run in, and the state resolvingSymlinksInPath() alone cannot
        // resolve, since it no-ops on a path that doesn't exist yet.
        let candidate = appSupportBabelotter.appending(path: "history.sqlite")

        #expect(throws: StorageLocationError.self) { try sandboxLocator.validate(candidate) }
    }

    @Test("rejects a symlink at an intermediate component, above the leaf")
    func rejectsSymlinkAtIntermediateComponent() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let appSupportAlias = sandbox.appending(path: "Documents/AppSupportAlias")
        try FileManager.default.createDirectory(at: appSupportAlias, withIntermediateDirectories: true)

        let libraryDirectory = sandbox.appending(path: "Library")
        try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        let appSupportLink = libraryDirectory.appending(path: "Application Support")
        // "Application Support" itself is the symlink, two levels above the leaf.
        try FileManager.default.createSymbolicLink(at: appSupportLink, withDestinationURL: appSupportAlias)

        let sandboxLocator = StorageLocator(home: sandbox, iCloudRoots: [sandbox.appending(path: "Documents")])
        let candidate = appSupportLink.appending(path: "ch.babelotter/history.sqlite")

        #expect(throws: StorageLocationError.self) { try sandboxLocator.validate(candidate) }
    }

    @Test("rejects via a root that is itself a symlink, when the candidate names the real target directly")
    func rejectsWhenRootItselfIsASymlink() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        // Simulates Desktop & Documents sync: ~/Documents is itself a symlink
        // into the real, backing iCloud container.
        let realContainer = sandbox.appending(path: "RealCloudContainer/Documents")
        try FileManager.default.createDirectory(at: realContainer, withIntermediateDirectories: true)
        let documentsAlias = sandbox.appending(path: "Documents")
        try FileManager.default.removeItem(at: documentsAlias)  // makeSandbox created a real dir here
        try FileManager.default.createSymbolicLink(at: documentsAlias, withDestinationURL: realContainer)

        // The injected root is the alias; the candidate names the real backing
        // path directly, never mentioning the alias at all.
        let sandboxLocator = StorageLocator(home: sandbox, iCloudRoots: [documentsAlias])
        let candidate = realContainer.appending(path: "history.sqlite")

        #expect(throws: StorageLocationError.self) { try sandboxLocator.validate(candidate) }
    }

    @Test("a normal, non-symlinked safe path still validates")
    func normalSafePathStillValidatesWithRealResolver() throws {
        let sandbox = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let sandboxLocator = StorageLocator(home: sandbox, iCloudRoots: [sandbox.appending(path: "Documents")])
        let candidate = sandbox.appending(path: "Library/Application Support/ch.babelotter/history.sqlite")

        try sandboxLocator.validate(candidate)
    }

    // MARK: - Fix round 1, Q2: the resolver seam, tested purely (no disk)
    //
    // These prove validate() actually consults `resolve`'s output for the
    // comparison — independent of whether the real filesystem algorithm above
    // is correct — using fake resolvers with no filesystem access at all.

    @Test("validate() rejects when the injected resolver maps a safe-looking candidate into a synced root")
    func validateHonorsResolvedCandidate() {
        let spoofingLocator = StorageLocator(
            home: home,
            iCloudRoots: [URL(filePath: "/Users/example/Documents")],
            resolve: { _ in URL(filePath: "/Users/example/Documents/resolved-target") }
        )
        let innocuousLooking = URL(filePath: "/Users/example/Library/Application Support/ch.babelotter/history.sqlite")
        #expect(throws: StorageLocationError.self) { try spoofingLocator.validate(innocuousLooking) }
    }

    @Test("validate() rejects when the injected resolver maps a root onto the candidate's real location")
    func validateHonorsResolvedRoot() {
        let candidate = URL(filePath: "/Users/example/Library/Application Support/ch.babelotter/history.sqlite")
        let rootLooksSafeButResolvesToCandidate = StorageLocator(
            home: home,
            iCloudRoots: [URL(filePath: "/Users/example/SomeAliasNameThatLooksSafe")],
            resolve: { url in
                url.path(percentEncoded: false).hasSuffix("SomeAliasNameThatLooksSafe")
                    ? URL(filePath: "/Users/example/Library/Application Support/ch.babelotter")
                    : url
            }
        )
        #expect(throws: StorageLocationError.self) { try rootLooksSafeButResolvesToCandidate.validate(candidate) }
    }

    @Test("validate() with an identity resolver behaves exactly as the pre-resolution comparison did")
    func identityResolverPreservesOriginalBehavior() throws {
        let pureLocator = StorageLocator(
            home: home,
            iCloudRoots: [URL(filePath: "/Users/example/Documents")],
            resolve: { $0 }
        )
        #expect(throws: StorageLocationError.self) {
            try pureLocator.validate(URL(filePath: "/Users/example/Documents/history.sqlite"))
        }
        try pureLocator.validate(URL(filePath: "/Users/example/DocumentsArchive/history.sqlite"))
    }
}

/// Pure, disk-free unit tests for the walk-up algorithm itself, against fake
/// `exists`/`resolveSymlinks` closures. Exercises `resolveAsFarAsExists`
/// directly rather than through `StorageLocator`, so the walking logic is
/// verified independently of both the real filesystem and the case-folding /
/// component-boundary comparison.
@Suite("StorageLocator.resolveAsFarAsExists walks to the deepest existing ancestor")
struct ResolveAsFarAsExistsTests {

    @Test("when the full path exists, resolveSymlinks runs on the full path with no walking")
    func fullPathExists() {
        let url = URL(filePath: "/fake/a/b/c")
        var resolveSymlinksCalledWith: URL?
        let result = StorageLocator.resolveAsFarAsExists(
            url,
            exists: { _ in true },
            resolveSymlinks: { resolveSymlinksCalledWith = $0; return $0 }
        )
        #expect(resolveSymlinksCalledWith == url)
        #expect(result.path(percentEncoded: false) == "/fake/a/b/c")
    }

    @Test("when only the parent exists, walks up once and re-appends the leaf")
    func onlyParentExists() {
        let url = URL(filePath: "/fake/a/b/c")
        let existing: Set<String> = ["/fake/a/b"]
        let result = StorageLocator.resolveAsFarAsExists(
            url,
            exists: { existing.contains($0.path(percentEncoded: false)) },
            resolveSymlinks: { existingURL in
                // Simulate "/fake/a/b" being a symlink to "/real/b".
                existingURL.path(percentEncoded: false) == "/fake/a/b"
                    ? URL(filePath: "/real/b")
                    : existingURL
            }
        )
        #expect(result.path(percentEncoded: false) == "/real/b/c")
    }

    @Test("when nothing exists except the volume root, walks all the way up")
    func nothingExistsExceptRoot() {
        let url = URL(filePath: "/fake/a/b/c")
        let result = StorageLocator.resolveAsFarAsExists(
            url,
            exists: { $0.path(percentEncoded: false) == "/" },
            resolveSymlinks: { $0 }
        )
        #expect(result.path(percentEncoded: false) == "/fake/a/b/c")
    }
}
