import Foundation

/// Locates the repository's source tree from this file's own compile-time path,
/// so architecture tests can read and assert about the code that ships.
enum SourceTree {
    /// `.../Tests/BabelOtterKitTests/Support/SourceTree.swift` → repository root.
    static let repositoryRoot: URL = URL(filePath: #filePath)
        .deletingLastPathComponent()   // Support
        .deletingLastPathComponent()   // BabelOtterKitTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repository root

    static var sourcesDirectory: URL { repositoryRoot.appending(path: "Sources") }

    /// Every `.swift` file in one target, sorted for deterministic failure output.
    static func swiftFiles(inTarget target: String) throws -> [URL] {
        try swiftFiles(under: sourcesDirectory.appending(path: target))
    }

    /// Every `.swift` file under `Sources/`, across all targets.
    static func allSourceFiles() throws -> [URL] {
        try swiftFiles(under: sourcesDirectory)
    }

    static func swiftFiles(under directory: URL) throws -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }

        var found: [URL] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            found.append(url)
        }
        return found.sorted { $0.path < $1.path }
    }

    static func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// Path relative to the repository root, for readable assertion messages.
    static func relativePath(_ url: URL) -> String {
        url.path(percentEncoded: false)
            .replacingOccurrences(of: repositoryRoot.path(percentEncoded: false), with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
