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

    @Test("every resolved dependency is on the allowlist")
    func resolvedDependenciesAreAllowlisted() throws {
        let url = SourceTree.repositoryRoot.appending(path: "Package.resolved")
        guard let data = try? Data(contentsOf: url) else {
            return  // no dependencies at all — the desired state
        }
        let identities = try ResolvedDependenciesDecoder.identities(from: data)
        let permitted = try Self.allowlist()

        let unapproved = identities
            .map { $0.lowercased() }
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

    /// The declarations whose identity is not on `permitted`.
    ///
    /// A declaration this scanner cannot extract an identity from counts as
    /// **unreviewed, not clean** — the same ruling as
    /// `ResolvedDependenciesDecoder`'s unrecognised schema. A guard that
    /// cannot read its input has not cleared it.
    ///
    /// This replaces the prior `declarations.isEmpty || !permitted.isEmpty`
    /// formulation, which never compared a declaration against the allowlist
    /// at all: it asserted only "either nothing is declared, or the allowlist
    /// is non-empty". With an empty allowlist that reduces to
    /// `declarations.isEmpty` and appears to work — but the first entry added
    /// to the allowlist, which is the documented procedure for adding a
    /// reviewed dependency, makes the right-hand side permanently true and
    /// both guards vacuous forever. The act the guard gates was the act that
    /// disabled it. Verified before the fix: with a hostile
    /// `.package(url: ".../swift-log.git", ...)` present, the old assertion
    /// passed for an allowlist of `{"sneakysdk"}`.
    static func unreviewed(_ declarations: [String], permitted: Set<String>) -> [String] {
        declarations.filter { declaration in
            guard let identity = PackageManifestScanner.identity(of: declaration) else {
                return true  // unparseable ⇒ unreviewed
            }
            return !permitted.contains(identity.lowercased())
        }
    }

    @Test("Package.swift declares no unreviewed package dependencies")
    func manifestDeclaresNoUnreviewedPackages() throws {
        let manifest = try SourceTree.read(
            SourceTree.repositoryRoot.appending(path: "Package.swift")
        )
        let declarations = PackageManifestScanner.declarations(withPrefix: ".package(", in: manifest)

        let permitted = try Self.allowlist()
        let unreviewed = Self.unreviewed(declarations, permitted: permitted)

        #expect(
            unreviewed.isEmpty,
            Comment(rawValue:
                "Package.swift declares dependencies that are not on "
                + "Config/dependency-allowlist.txt:\n"
                + unreviewed.joined(separator: "\n")
                + "\n\nA declaration this scan cannot extract an identity from is listed "
                + "here too: an unparseable declaration is unreviewed, not clean. Add the "
                + "identity to Config/dependency-allowlist.txt in a commit that says what "
                + "the package does and confirms it performs no networking."
            )
        )
    }

    /// `.binaryTarget(url:checksum:)` is declared under `targets:`, not
    /// `dependencies:`, so the `.package(`-prefix scan above never sees it —
    /// and unlike a source-control dependency, it may not produce a
    /// `Package.resolved` pin either. That is a live route for unaudited
    /// third-party binary code to enter a process holding the user's
    /// writing, invisible to both other checks in this suite.
    ///
    /// Proof this fires lives in `manifestScannerCatchesAnUnreviewedBinaryTarget`
    /// below, against synthetic manifest text, not against a live edit to
    /// `Package.swift`: SwiftPM validates every declared binary target's
    /// artifact during package resolution, before the test binary ever runs
    /// — a real `.binaryTarget(url:checksum:)` or `.binaryTarget(path:)`
    /// pointing at a missing/invalid artifact aborts `swift test` itself
    /// with a fatal error, never reaching this test at all. Confirmed
    /// empirically while preparing this fix (see the task report).
    @Test("Package.swift declares no unreviewed binary targets")
    func manifestDeclaresNoUnreviewedBinaryTargets() throws {
        let manifest = try SourceTree.read(
            SourceTree.repositoryRoot.appending(path: "Package.swift")
        )
        let declarations = PackageManifestScanner.declarations(withPrefix: ".binaryTarget(", in: manifest)

        let permitted = try Self.allowlist()
        let unreviewed = Self.unreviewed(declarations, permitted: permitted)

        #expect(
            unreviewed.isEmpty,
            Comment(rawValue:
                "Package.swift declares a binary target that is not on the allowlist:\n"
                + unreviewed.joined(separator: "\n")
                + "\n\n.binaryTarget pulls unaudited compiled code into the process "
                + "that holds the user's writing, and is invisible to the "
                + ".package( scan and possibly to Package.resolved as well. Review "
                + "it and add its identity to Config/dependency-allowlist.txt."
            )
        )
    }

    // MARK: - Manifest scanner coverage
    //
    // `manifestDeclaresNoUnreviewedBinaryTargets` cannot be proven by editing
    // the real `Package.swift`: SwiftPM validates every declared binary
    // target's artifact during package resolution, before `swift test`'s
    // test binary ever runs, so a planted `.binaryTarget(` pointing at a
    // missing artifact aborts the whole run with `fatalError` rather than
    // letting this suite's assertion fail. This exercises the same
    // `PackageManifestScanner.declarations` + empty-allowlist logic directly
    // against synthetic manifest text instead.

    @Test("manifest scanner catches an unreviewed binary target")
    func manifestScannerCatchesAnUnreviewedBinaryTarget() {
        let manifestWithUnreviewedBinaryTarget = """
        let package = Package(
            targets: [
                .binaryTarget(name: "SneakySDK", url: "https://example.com/sneaky.zip", checksum: "deadbeef"),
                .target(name: "BabelOtterKit"),
            ]
        )
        """
        let declarations = PackageManifestScanner.declarations(
            withPrefix: ".binaryTarget(",
            in: manifestWithUnreviewedBinaryTarget
        )
        #expect(declarations == [
            #".binaryTarget(name: "SneakySDK", url: "https://example.com/sneaky.zip", checksum: "deadbeef"),"#
        ])

        // This mirrors the real test's assertion exactly: with an empty
        // allowlist, a non-empty declarations list must fail it.
        #expect(!Self.unreviewed(declarations, permitted: []).isEmpty)

        // The allowlist entry that matches this declaration's identity lets it
        // pass...
        #expect(Self.unreviewed(declarations, permitted: ["sneakysdk"]).isEmpty)

        // ...and an allowlist entry that does NOT match must still fail. This
        // pair is the whole point: the previous version of this test asserted
        // `declarations.isEmpty || !reviewedAllowlist.isEmpty`, which passes
        // for *any* non-empty set — `["swift-log"]`, `["totally-unrelated"]`,
        // anything — so it read as though "sneakysdk" corresponded to the
        // planted `.binaryTarget(name: "SneakySDK", ...)` when it did not.
        #expect(Self.unreviewed(declarations, permitted: ["swift-log"]) == declarations)

        // No binary target at all must pass regardless of the allowlist.
        let cleanManifest = "let package = Package(targets: [.target(name: \"BabelOtterKit\")])"
        let cleanDeclarations = PackageManifestScanner.declarations(withPrefix: ".binaryTarget(", in: cleanManifest)
        #expect(cleanDeclarations.isEmpty)
        #expect(Self.unreviewed(cleanDeclarations, permitted: []).isEmpty)
    }

    @Test("manifest scanner: identities are extracted from every declaration shape", arguments: [
        (declaration: #".binaryTarget(name: "SneakySDK", url: "https://e.com/s.zip", checksum: "dead"),"#,
         identity: "SneakySDK"),
        (declaration: #".package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),"#,
         identity: "swift-log"),
        (declaration: #".package(url: "https://github.com/apple/swift-log", from: "1.0.0"),"#,
         identity: "swift-log"),
        (declaration: #".package(id: "apple.swift-log", from: "1.0.0"),"#,
         identity: "apple.swift-log"),
        (declaration: #".package(path: "../LocalSneakySDK"),"#,
         identity: "LocalSneakySDK"),
        (declaration: #".package(name: "Legacy", url: "https://github.com/x/legacy-pkg.git", from: "1.0.0"),"#,
         identity: "legacy-pkg"),
        // Unparseable ⇒ nil ⇒ counted as unreviewed by `unreviewed(_:permitted:)`.
        // A declaration split across lines reaches this scanner as a bare
        // `.package(` with its arguments on the following lines, so it lands
        // here rather than being silently cleared.
        (declaration: ".package(", identity: nil),
        (declaration: #".package(url: someVariable, from: "1.0.0"),"#, identity: nil),
    ] as [(declaration: String, identity: String?)])
    func manifestScannerExtractsIdentities(declaration: String, identity: String?) {
        #expect(PackageManifestScanner.identity(of: declaration) == identity)
    }

    @Test("manifest scanner: an unparseable declaration counts as unreviewed, not clean")
    func unparseableDeclarationIsUnreviewed() {
        // Even with a generous allowlist, a declaration whose identity cannot
        // be read must be reported. The alternative — treating "I could not
        // parse this" as "this is fine" — is exactly the Package.resolved
        // unrecognised-schema failure in a different costume.
        let unparseable = [".package("]
        #expect(Self.unreviewed(unparseable, permitted: ["sneakysdk", "swift-log"]) == unparseable)
    }

    // MARK: - Resolved-schema decoder coverage
    //
    // `resolvedDependenciesAreAllowlisted` is only as good as its decoder.
    // These exercise `ResolvedDependenciesDecoder` directly against sample
    // JSON, because a real `Package.resolved` cannot be planted for this
    // purpose: SwiftPM regenerates/deletes it to match `Package.swift` before
    // the test binary ever runs, so the decoder's behavior on schemas other
    // than "whatever the local toolchain currently writes" would otherwise go
    // completely unexercised.

    @Test("resolved schema decoder: recognised shapes decode correctly")
    func resolvedSchemaDecodingRecognisedShapes() throws {
        let v1 = Data("""
        {
          "object": {
            "pins": [
              {
                "package": "swift-algorithms",
                "repositoryURL": "https://github.com/apple/swift-algorithms",
                "state": { "branch": null, "revision": "abc123", "version": "1.0.0" }
              }
            ]
          },
          "version": 1
        }
        """.utf8)
        let v1Identities = try ResolvedDependenciesDecoder.identities(from: v1)
        #expect(v1Identities == ["swift-algorithms"])

        let v3 = Data("""
        {
          "pins": [
            {
              "identity": "swift-numerics",
              "kind": "remoteSourceControl",
              "location": "https://github.com/apple/swift-numerics",
              "state": { "revision": "def456", "version": "1.0.0" }
            }
          ],
          "version": 3
        }
        """.utf8)
        let v3Identities = try ResolvedDependenciesDecoder.identities(from: v3)
        #expect(v3Identities == ["swift-numerics"])

        // A recognised schema with genuinely zero pins is a real "no
        // dependencies" state, not a parse failure — it must decode cleanly
        // to an empty list, not throw.
        let genuinelyEmpty = Data(#"{"pins":[],"version":3}"#.utf8)
        let emptyIdentities = try ResolvedDependenciesDecoder.identities(from: genuinelyEmpty)
        #expect(emptyIdentities.isEmpty)
    }

    @Test("resolved schema decoder: an unrecognised schema fails loudly instead of decoding to zero pins")
    func resolvedSchemaDecodingUnrecognisedSchemaFails() {
        // A future/unknown schema version, with real pins present — this is
        // exactly the CFStream failure mode: if this silently decoded to
        // zero pins, unapproved dependencies would sail through unnoticed.
        let unknownVersion = Data(#"{"version":99,"pins":[{"identity":"sneaky-package"}]}"#.utf8)
        #expect(throws: ResolvedDependenciesDecoder.UnrecognisedSchema.self) {
            try ResolvedDependenciesDecoder.identities(from: unknownVersion)
        }

        // No version field at all must also fail loudly, not decode to [].
        let missingVersion = Data(#"{"pins":[{"identity":"sneaky-package"}]}"#.utf8)
        #expect(throws: (any Error).self) {
            try ResolvedDependenciesDecoder.identities(from: missingVersion)
        }
    }
}

/// Decodes `Package.resolved`, handling the schema shapes SwiftPM has
/// actually written: v1 nests pins under `object.pins` with a `package`
/// identity field; v2/v3 use a top-level `pins` array with an `identity`
/// field. Today's toolchain writes v3.
///
/// The prior version of this decoder declared `pins` as `Optional` at the
/// v2/v3 top level. An unrecognised schema — such as a genuine v1 file,
/// which has no top-level `pins` key at all — decoded successfully with
/// `pins == nil`, and `resolved.pins ?? []` turned that into a silent empty
/// list: the guard reported "no dependencies" for a file it never actually
/// understood. That is the same failure mode `"CFStream"` was: a check that
/// reads as coverage but verifies nothing for an input shape nobody tested.
/// This type instead requires every version it decodes to be one it
/// explicitly recognises, and throws `UnrecognisedSchema` otherwise — a
/// genuinely dependency-free `Package.resolved` (recognised schema, empty
/// `pins`) still decodes to `[]` and passes; an unrecognised one fails the
/// test instead of passing it.
enum ResolvedDependenciesDecoder {
    struct UnrecognisedSchema: Error, CustomStringConvertible {
        let version: Int?

        var description: String {
            let versionText = version.map(String.init) ?? "missing"
            return "Package.resolved's schema was not recognised (version: \(versionText)) — "
                + "this decoder only understands the v1 and v2/v3 pin layouts, so it could "
                + "not run the dependency-allowlist guard against this file. Teach "
                + "ResolvedDependenciesDecoder this schema before trusting the guard again."
        }
    }

    private struct VersionProbe: Decodable { let version: Int }

    private struct V1: Decodable {
        struct Object: Decodable {
            struct Pin: Decodable { let package: String }
            let pins: [Pin]
        }
        let object: Object
    }

    private struct V2Plus: Decodable {
        struct Pin: Decodable { let identity: String }
        let pins: [Pin]
    }

    /// The identity of every resolved pin, in the case as written in the
    /// file. Throws `UnrecognisedSchema` if `data`'s `version` is not one
    /// this decoder understands, rather than silently returning `[]`.
    static func identities(from data: Data) throws -> [String] {
        let version = (try? JSONDecoder().decode(VersionProbe.self, from: data))?.version

        switch version {
        case 1:
            let decoded = try JSONDecoder().decode(V1.self, from: data)
            return decoded.object.pins.map { $0.package }
        case 2, 3:
            let decoded = try JSONDecoder().decode(V2Plus.self, from: data)
            return decoded.pins.map { $0.identity }
        default:
            throw UnrecognisedSchema(version: version)
        }
    }
}

/// Extracts the trimmed, prefix-matching declaration lines from `Package.swift`
/// text — shared by the `.package(` and `.binaryTarget(` scans, and directly
/// unit-testable against synthetic manifest text (see
/// `manifestScannerCatchesAnUnreviewedBinaryTarget`), since a real
/// `Package.swift` edit that declares an invalid binary target cannot survive
/// long enough for `swift test` to observe this suite's own assertion fail.
enum PackageManifestScanner {
    static func declarations(withPrefix prefix: String, in manifest: String) -> [String] {
        manifest
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix(prefix) }
    }

    /// Argument labels that carry a dependency's identity, in the order
    /// SwiftPM itself prefers. A registry `id:` is already the identity; a
    /// `url:`/`location:`/`path:` identity is its last path component with
    /// any `.git` suffix removed (`.../swift-log.git` → `swift-log`), which
    /// is how SwiftPM derives one; `name:` is last because on `.package` it
    /// is a deprecated alias.
    ///
    /// `.binaryTarget` is the exception and gets `name:` only: its `url:` is
    /// the artifact download (`.../SneakySDK-1.0.xcframework.zip`), which is
    /// not the target's identity — reading it as one would put a zip filename
    /// on the allowlist and quietly stop matching the moment the version in
    /// that filename changed.
    private static func identityLabels(for declaration: String) -> [String] {
        declaration.hasPrefix(".binaryTarget(")
            ? ["name"]
            : ["id", "url", "location", "path", "name"]
    }

    /// The identity of a single declaration line, or `nil` if this scanner
    /// cannot read one.
    ///
    /// `nil` means "unparseable", and callers must treat that as **unreviewed**
    /// rather than clean — see `DependencyAllowlistTests.unreviewed(_:permitted:)`.
    /// The realistic `nil` cases are a declaration split across several lines
    /// (this scanner is line-based, so it sees only `.package(`) and one whose
    /// URL comes from a variable rather than a string literal. Both are
    /// situations where a human should look, not situations where a guard
    /// should shrug.
    static func identity(of declaration: String) -> String? {
        for label in identityLabels(for: declaration) {
            guard let raw = quotedArgument(labelled: label, in: declaration), !raw.isEmpty else {
                continue
            }
            let lastComponent = raw.split(separator: "/").last.map(String.init) ?? raw
            let candidate = (label == "id" || label == "name") ? raw : lastComponent
            let identity = candidate.hasSuffix(".git") ? String(candidate.dropLast(4)) : candidate
            return identity.isEmpty ? nil : identity
        }
        return nil
    }

    /// The string literal given for `label:`, e.g. `url: "https://…"` → the URL.
    /// The label must sit on an argument boundary, so `url:` cannot be matched
    /// inside some longer label that merely ends with those characters.
    private static func quotedArgument(labelled label: String, in declaration: String) -> String? {
        var searchStart = declaration.startIndex
        while let labelRange = declaration.range(of: "\(label):", range: searchStart..<declaration.endIndex) {
            searchStart = labelRange.upperBound
            let precedingIsBoundary: Bool
            if labelRange.lowerBound == declaration.startIndex {
                precedingIsBoundary = true
            } else {
                let preceding = declaration[declaration.index(before: labelRange.lowerBound)]
                precedingIsBoundary = preceding == "(" || preceding == "," || preceding.isWhitespace
            }
            guard precedingIsBoundary else { continue }

            // The value must be a string literal, and it must be the *next*
            // thing after the label — `url: someVariable` yields nil rather
            // than reaching forward and stealing a later argument's literal.
            let rest = declaration[labelRange.upperBound...]
            guard let firstNonSpace = rest.firstIndex(where: { !$0.isWhitespace }),
                  rest[firstNonSpace] == "\"" else { return nil }
            let contentStart = rest.index(after: firstNonSpace)
            guard let closingQuote = rest[contentStart...].firstIndex(of: "\"") else { return nil }
            return String(rest[contentStart..<closingQuote])
        }
        return nil
    }
}
