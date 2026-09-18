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
}
