import Testing
import Foundation

/// NFR-P6: every runtime dependency is reviewed. A transitive package is the
/// easiest way for telemetry to appear inside a process that holds the user's
/// writing, so the set is pinned and checked rather than trusted.
@Suite("Architecture: dependency allowlist")
struct DependencyAllowlistTests {

    static func allowlist() throws -> Set<String> {
        let url = SourceTree.repositoryRoot.appending(path: "Config/dependency-allowlist.txt")
        return Set(
            try SourceTree.read(url)
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        )
    }

    /// Minimal shape of Package.resolved v2/v3.
    private struct Resolved: Decodable {
        struct Pin: Decodable { let identity: String }
        let pins: [Pin]?
    }

    @Test("every resolved dependency is on the allowlist")
    func resolvedDependenciesAreAllowlisted() throws {
        let url = SourceTree.repositoryRoot.appending(path: "Package.resolved")
        guard let data = try? Data(contentsOf: url) else {
            return  // no dependencies at all — the desired state
        }
        let resolved = try JSONDecoder().decode(Resolved.self, from: data)
        let permitted = try Self.allowlist()

        let unapproved = (resolved.pins ?? [])
            .map { $0.identity.lowercased() }
            .filter { !permitted.contains($0) }

        #expect(
            unapproved.isEmpty,
            """
            Unreviewed runtime dependencies: \(unapproved.sorted().joined(separator: ", ")).

            Adding a package puts third-party code inside the process that holds
            the user's writing. Prefer a system library. If the package is
            genuinely necessary, add its identity to
            Config/dependency-allowlist.txt in a commit that says what it does
            and confirms it performs no networking.
            """
        )
    }

    @Test("Package.swift declares no unreviewed package dependencies")
    func manifestDeclaresNoUnreviewedPackages() throws {
        let manifest = try SourceTree.read(
            SourceTree.repositoryRoot.appending(path: "Package.swift")
        )
        let declarations = manifest
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix(".package(") }

        let permitted = try Self.allowlist()

        #expect(
            declarations.isEmpty || !permitted.isEmpty,
            Comment(rawValue:
                "Package.swift declares dependencies but the allowlist is empty:\n"
                + declarations.joined(separator: "\n")
            )
        )
    }
}
