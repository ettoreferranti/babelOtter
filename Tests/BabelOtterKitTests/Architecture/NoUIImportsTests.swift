import Testing
import Foundation

/// NFR-Q3: the core package must be runnable without AppKit, a window server or a
/// user session. That is what makes it unit-testable, mutation-testable, and what
/// keeps the privacy invariants provable — none of which survive a UI import.
@Suite("Architecture: core imports no UI framework")
struct NoUIImportsTests {
    static let bannedModules = ["AppKit", "SwiftUI", "UIKit", "Cocoa", "Carbon"]

    @Test("BabelOtterKit imports no UI framework")
    func coreImportsNoUIFramework() throws {
        var violations: [String] = []

        for file in try SourceTree.swiftFiles(inTarget: "BabelOtterKit") {
            let contents = try SourceTree.read(file)
            for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("import ") else { continue }
                let module = trimmed
                    .dropFirst("import ".count)
                    .trimmingCharacters(in: .whitespaces)
                if Self.bannedModules.contains(module) {
                    violations.append("\(SourceTree.relativePath(file)) imports \(module)")
                }
            }
        }

        #expect(
            violations.isEmpty,
            """
            BabelOtterKit must import no UI framework (NFR-Q3).
            Move this code into BabelOtterApp and talk to it through a protocol.
            Violations:
            \(violations.joined(separator: "\n"))
            """
        )
    }

    @Test("the source tree helper actually finds sources")
    func sourceTreeResolves() throws {
        let files = try SourceTree.swiftFiles(inTarget: "BabelOtterKit")
        #expect(!files.isEmpty, "SourceTree found no files — its path arithmetic is wrong")
    }
}
