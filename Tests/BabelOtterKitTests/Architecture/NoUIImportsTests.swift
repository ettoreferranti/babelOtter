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
                if let module = ImportLineMatcher.bannedModule(in: String(line), bannedModules: Self.bannedModules) {
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

    // MARK: - Matcher coverage
    //
    // The scan above is only as good as its line matcher. These cases were found
    // by review, not by imagination: each is a realistic way `import AppKit`
    // could be written that a naive `hasPrefix("import ")` + exact-match check
    // would miss, plus the look-alikes that must NOT be flagged.

    @Test("import line matcher: evasions are caught, look-alikes are not", arguments: [
        // Evasions: each of these imports AppKit and must be caught.
        (line: "@preconcurrency import AppKit", expected: "AppKit"),
        (line: "import AppKit.NSWindow", expected: "AppKit"),
        (line: "import AppKit // temporary", expected: "AppKit"),
        (line: "import struct AppKit.NSView", expected: "AppKit"),
        // Look-alikes: none of these import a banned module and must NOT be caught.
        (line: "import Foundation", expected: nil),
        (line: "import FoundationNetworking", expected: nil),
        (line: "import AppKitExtras", expected: nil),                              // prefix trap
        (line: "let message = \"you must not import AppKit here\"", expected: nil), // string literal
        (line: "// a comment that mentions import AppKit is banned", expected: nil), // comment
    ] as [(line: String, expected: String?)])
    func importLineMatcherHandlesEvasions(line: String, expected: String?) {
        #expect(ImportLineMatcher.bannedModule(in: line, bannedModules: Self.bannedModules) == expected)
    }
}

/// Extracts the module an `import` line names, tolerant of the ways a real
/// import declaration can be written — so the NFR-Q3 guard above can't be
/// evaded by spelling, only by genuinely not importing the module.
enum ImportLineMatcher {
    /// Declaration kinds that may appear between `import` and the module path,
    /// e.g. `import struct Foundation.URL`.
    private static let importDeclarationKinds: Set<String> = [
        "struct", "class", "enum", "protocol", "typealias", "func", "var", "let",
    ]

    /// Returns the banned module `line` imports, or `nil` if `line` is not an
    /// import declaration, or the module it names is not banned.
    static func bannedModule(in line: String, bannedModules: [String]) -> String? {
        // 1. Drop a trailing `//` comment before tokenizing, so `import AppKit
        //    // temporary` doesn't glue "AppKit" to comment text.
        let codePortion: Substring
        if let commentRange = line.range(of: "//") {
            codePortion = line[line.startIndex..<commentRange.lowerBound]
        } else {
            codePortion = line[...]
        }

        var tokens = codePortion
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        // 2. Drop leading attributes: `@preconcurrency import AppKit`,
        //    `@_exported import AppKit`, and so on.
        while let first = tokens.first, first.hasPrefix("@") {
            tokens.removeFirst()
        }

        // 3. What's left must start with the `import` keyword, or this line is
        //    not an import declaration at all — including a comment or string
        //    literal that merely contains the words "import AppKit".
        guard tokens.first == "import" else { return nil }
        tokens.removeFirst()

        // 4. An optional declaration kind: `import struct AppKit.NSView` names
        //    a single symbol, not the whole module, but it still pulls AppKit in.
        if let kind = tokens.first, importDeclarationKinds.contains(kind) {
            tokens.removeFirst()
        }

        // 5. Whatever remains is the module path. Compare only its root
        //    component (`AppKit.NSWindow` → `AppKit`), and only by exact
        //    match, so `AppKitExtras` does not match banned `AppKit`.
        guard let modulePath = tokens.first else { return nil }
        let rootModule = modulePath.split(separator: ".", maxSplits: 1).first.map(String.init) ?? modulePath

        return bannedModules.contains(rootModule) ? rootModule : nil
    }
}
